package print

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
)

type PrintDaemon struct {
	service     *PrintService
	printingDir string
}

func NewPrintDaemon(service *PrintService, printingDir string) *PrintDaemon {
	return &PrintDaemon{
		service:     service,
		printingDir: printingDir,
	}
}

func (d *PrintDaemon) SyncAndStart(ctx context.Context) {
	// Create directory if not exists
	if err := os.MkdirAll(d.printingDir, 0755); err != nil {
		log.Printf("[PrintDaemon] Failed to create printing directory %s: %v", d.printingDir, err)
	}

	// Ticker every 2 seconds
	ticker := time.NewTicker(2 * time.Second)
	go func() {
		log.Println("[PrintDaemon] Background folder monitor started (polling every 2 seconds)...")

		// Run a Tick immediately on startup
		d.Tick(ctx)

		for {
			select {
			case <-ctx.Done():
				ticker.Stop()
				return
			case <-ticker.C:
				d.Tick(ctx)
			}
		}
	}()
}

func (d *PrintDaemon) Tick(ctx context.Context) {
	// Check if directory exists, if not create it
	if _, err := os.Stat(d.printingDir); os.IsNotExist(err) {
		if err := os.MkdirAll(d.printingDir, 0755); err != nil {
			log.Printf("[PrintDaemon] Error creating directory: %v", err)
			return
		}
	}

	// 1. Read directory
	files, err := os.ReadDir(d.printingDir)
	if err != nil {
		log.Printf("[PrintDaemon] Error reading directory: %v", err)
		return
	}

	// Check if directory is empty (ignore hidden files like .DS_Store)
	isEmpty := true
	for _, f := range files {
		if f.Name() != ".DS_Store" && !f.IsDir() {
			isEmpty = false
			break
		}
	}

	// If directory is not empty, wait until printer consumes the active PDF file
	if !isEmpty {
		return
	}

	// 2. Directory is empty!
	// Let's get the latest job with status 'Printing'
	latestPrintingJob, err := d.service.GetLatestPrintingJob(ctx)
	if err == nil {
		// A 'Printing' job exists, but the folder is empty, which means the file was deleted by the printer.
		// We must mark this printing job as Completed.
		log.Printf("[PrintDaemon] Found finished print job %s (file has been printed and removed). Patching status to Completed.", latestPrintingJob.PrintJobID)
		completedStatus := "Completed"
		_, updateErr := d.service.UpdatePrintJobStatus(ctx, latestPrintingJob.PrintJobID, &completedStatus, nil, nil)
		if updateErr != nil {
			log.Printf("[PrintDaemon] Error patching job %s to Completed: %v", latestPrintingJob.PrintJobID, updateErr)
			return
		}
	} else if err != sql.ErrNoRows {
		log.Printf("[PrintDaemon] Error fetching latest printing job: %v", err)
		return
	}

	// 3. Now get the next Pending job (highest priority, oldest creation time)
	pendingJob, err := d.service.PollPrintJob(ctx)
	if err != nil {
		if err == sql.ErrNoRows {
			// No pending print jobs in the queue
			return
		}
		log.Printf("[PrintDaemon] Error polling pending print job: %v", err)
		return
	}

	log.Printf("[PrintDaemon] Polled pending print job %s. Preparing to print.", pendingJob.PrintJobID)

	// 4. Update status to Printing immediately
	printingStatus := "Printing"
	updatedJob, err := d.service.UpdatePrintJobStatus(ctx, pendingJob.PrintJobID, &printingStatus, nil, nil)
	if err != nil {
		log.Printf("[PrintDaemon] Error updating print job status to Printing: %v", err)
		return
	}

	// 5. Generate PDF bytes
	pdfBytes, err := d.service.GenerateSingleJobPDF(ctx, updatedJob)
	if err != nil {
		log.Printf("[PrintDaemon] Error generating PDF for print job %s: %v. Marking job as Failed.", updatedJob.PrintJobID, err)
		failedStatus := "Failed"
		_, _ = d.service.UpdatePrintJobStatus(ctx, updatedJob.PrintJobID, &failedStatus, nil, nil)
		return
	}

	// 6. Write PDF file to the printing directory
	fileName := fmt.Sprintf("print_job_%s.pdf", updatedJob.PrintJobID.String())
	filePath := filepath.Join(d.printingDir, fileName)
	err = os.WriteFile(filePath, pdfBytes, 0644)
	if err != nil {
		log.Printf("[PrintDaemon] Error writing PDF to %s: %v. Reverting status to Failed.", filePath, err)
		failedStatus := "Failed"
		_, _ = d.service.UpdatePrintJobStatus(ctx, updatedJob.PrintJobID, &failedStatus, nil, nil)
		return
	}

	log.Printf("[PrintDaemon] PDF successfully written to %s. Status set to Printing. Monitoring directory.", filePath)
}
