package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/alexbrainman/printer"
	"github.com/fsnotify/fsnotify"
)

type Config struct {
	WatchDir      string `json:"watch_dir"`
	LogDir        string `json:"log_dir"`
	TargetPrinter string `json:"target_printer"`
}

func loadConfig() Config {
	defaultConfig := Config{
		WatchDir:      "jobs",
		LogDir:        "logs",
		TargetPrinter: "FF Q504h for DocuPrint M115 w",
	}

	exePath, err := os.Executable()
	if err != nil {
		return defaultConfig
	}
	configPath := filepath.Join(filepath.Dir(exePath), "config.json")

	// Create default config file if it does not exist
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		data, err := json.MarshalIndent(defaultConfig, "", "  ")
		if err == nil {
			_ = os.WriteFile(configPath, data, 0644)
		}
		return defaultConfig
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		return defaultConfig
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return defaultConfig
	}

	// Fallback to default values if fields are empty
	if config.WatchDir == "" {
		config.WatchDir = defaultConfig.WatchDir
	}
	if config.LogDir == "" {
		config.LogDir = defaultConfig.LogDir
	}
	if config.TargetPrinter == "" {
		config.TargetPrinter = defaultConfig.TargetPrinter
	}

	return config
}

func main() {
	// Load config from JSON file (defaults to config.json in the same directory as the .exe)
	cfg := loadConfig()

	// Declare Command Line Flags to override configuration if necessary
	printerFlag := flag.String("printer", "", "Target printer name (Overrides config file)")
	watchDirFlag := flag.String("watch", "", "Watched directory path (Overrides config file)")
	logDirFlag := flag.String("log", "", "Log directory path (Overrides config file)")
	flag.Parse()

	// Priority: Command Line Flags -> Config File -> Default
	watchDir := cfg.WatchDir
	if *watchDirFlag != "" {
		watchDir = *watchDirFlag
	}

	logDir := cfg.LogDir
	if *logDirFlag != "" {
		logDir = *logDirFlag
	}

	targetPrinter := cfg.TargetPrinter
	if *printerFlag != "" {
		targetPrinter = *printerFlag
	}

	// Automatically convert relative paths to absolute paths based on the .exe location
	exePath, err := os.Executable()
	var exeDir string
	if err == nil {
		exeDir = filepath.Dir(exePath)
	} else {
		exeDir = "."
	}

	if !filepath.IsAbs(watchDir) {
		watchDir = filepath.Join(exeDir, watchDir)
	}

	if !filepath.IsAbs(logDir) {
		logDir = filepath.Join(exeDir, logDir)
	}

	// 1. Check and automatically create watched directory (if missing)
	if _, err := os.Stat(watchDir); os.IsNotExist(err) {
		_ = os.MkdirAll(watchDir, 0755)
	}

	// 2. Check and automatically create log directory (if missing)
	if _, err := os.Stat(logDir); os.IsNotExist(err) {
		_ = os.MkdirAll(logDir, 0755)
	}

	// --- CONFIGURE LOGGING TO BOTH CONSOLE AND FILE ---
	logFile, err := os.OpenFile(filepath.Join(logDir, "agent_log.txt"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err == nil {
		// Use io.MultiWriter to write logs to both file and current CMD/PowerShell console
		mw := io.MultiWriter(os.Stdout, logFile)
		log.SetOutput(mw)
	} else {
		log.Printf("⚠️ Unable to open log file: %v. Logging to console only.\n", err)
	}
	defer func() {
		if logFile != nil {
			logFile.Close()
		}
	}()
	// -----------------------------------------------------------------

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Fatal("❌ Error initializing watcher: ", err)
	}
	defer watcher.Close()

	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}
				// Listen for all change events in the directory
				if event.Has(fsnotify.Create) || event.Has(fsnotify.Write) {
					// Check if the file actually exists on disk (to avoid processing old events of deleted files)
					if _, err := os.Stat(event.Name); os.IsNotExist(err) {
						continue
					}

					filename := filepath.Base(event.Name)
					ext := strings.ToLower(filepath.Ext(event.Name))

					// Print debug log to let the user know the program detected the added file
					log.Printf("🔍 Detected new/modified file: %s (Action: %v)\n", filename, event.Op)

					if ext == ".pdf" {
						log.Printf("⏳ Checking file write status: %s...\n", filename)
						// Wait for the file to be fully written (to avoid file lock/busy errors)
						if !waitForFileRelease(event.Name, 5*time.Second) {
							log.Printf("⚠️ Skipping file: %s is locked by another process for more than 5 seconds.\n", filename)
							continue
						}

						// Wait until the printer is ready (online and idle) before sending a new print job
						waitUntilPrinterIsReady(targetPrinter)

						log.Printf("➔ Received file: %s. Sending print command to printer '%s'...\n", filename, targetPrinter)

						err := printFile(event.Name, targetPrinter)
						if err != nil {
							log.Printf("❌ Error sending print command for file %s: %v\n", filename, err)
							continue
						}

						log.Println("⏳ Waiting for printer to complete the task...")
						waitUntilPrinterIsClean(targetPrinter, event.Name)

						// Only when Jobs == 0 (printing finished) do we delete the intermediate file
						log.Printf("✓ Print successful! Deleting intermediate file: %s\n", filename)
						_ = os.Remove(event.Name)
					} else {
						log.Printf("ℹ️ Skipping file %s (only PDF files are supported)\n", filename)
					}
				}
			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				log.Println("❌ Watcher error:", err)
			}
		}
	}()

	err = watcher.Add(watchDir)
	if err != nil {
		log.Fatalf("❌ Error: Unable to watch directory '%s': %v\n", watchDir, err)
	}

	log.Printf("🚀 Windows Agent started successfully!\n")
	log.Printf("📂 Watched directory: %s\n", watchDir)
	log.Printf("🖨️ Target printer: %s\n", targetPrinter)
	log.Printf("📝 Log file: %s\n", filepath.Join(logDir, "agent_log.txt"))
	log.Printf("--------------------------------------------------\n")

	select {}
}

func printFile(filePath string, printerName string) error {
	// Get the directory path containing the current agent.exe
	exePath, err := os.Executable()
	var pdfToPrinterPath string
	if err == nil {
		pdfToPrinterPath = filepath.Join(filepath.Dir(exePath), "PDFtoPrinter.exe")
	}

	// Check if PDFtoPrinter.exe exists in the same directory
	if pdfToPrinterPath != "" {
		if _, err := os.Stat(pdfToPrinterPath); err == nil {
			log.Printf("ℹ️ Using PDFtoPrinter.exe for highly stable silent printing...")
			cmd := exec.Command(pdfToPrinterPath, filePath, printerName)
			cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
			return cmd.Run()
		}
	}

	// Fallback to legacy PowerShell command if PDFtoPrinter.exe is not found
	log.Printf("⚠️ PDFtoPrinter.exe not found. Falling back to PowerShell command...")
	cmdStr := fmt.Sprintf(`Start-Process -FilePath "%s" -Verb PrintTo -ArgumentList "%s" -PassThru | Out-Null`, filePath, printerName)
	cmd := exec.Command("powershell", "-Command", cmdStr)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return cmd.Run()
}

func waitUntilPrinterIsReady(printerName string) {
	p, err := printer.Open(printerName)
	if err != nil {
		log.Printf("❌ Unable to connect to printer '%s'. Please check connection/cables! Retrying in 5 seconds...\n", printerName)
		time.Sleep(5 * time.Second)
		waitUntilPrinterIsReady(printerName)
		return
	}
	defer p.Close()

	startTime := time.Now()
	lastAlertTime := time.Now()

	firstCheck := true
	for {
		jobs, err := p.Jobs()
		if err != nil {
			log.Printf("⚠️ Error checking printer status: %v. Retrying in 2 seconds...\n", err)
			time.Sleep(2 * time.Second)
			continue
		}

		if len(jobs) == 0 {
			if !firstCheck {
				log.Println("✓ Printer is idle and ready for new commands.")
			}
			return
		}

		firstCheck = false
		log.Printf("⏳ Printer is busy (currently %d print job(s) pending). Waiting for printer to become idle...\n", len(jobs))
		time.Sleep(3 * time.Second)

		if time.Since(startTime) > 1*time.Minute && time.Since(lastAlertTime) > 1*time.Minute {
			log.Printf("🚨 WARNING: Printer has been busy/stuck for over 1 minute. Please check paper tray/paper jam!\n")
			lastAlertTime = time.Now()
		}
	}
}

func waitUntilPrinterIsClean(printerName string, filePath string) {
	p, err := printer.Open(printerName)
	if err != nil {
		log.Println("❌ Unable to connect to printer, retrying in 5 seconds...")
		time.Sleep(5 * time.Second)
		waitUntilPrinterIsClean(printerName, filePath)
		return
	}
	defer p.Close()

	// Step 1: Wait for the print job to appear in the printer queue (Windows Spooler detects the Job)
	// Wait up to 5 seconds (check every 500ms)
	jobAppeared := false
	for i := 0; i < 10; i++ {
		jobs, err := p.Jobs()
		if err == nil && len(jobs) > 0 {
			jobAppeared = true
			log.Printf("📥 Detected %d print job(s) loading into the queue.\n", len(jobs))
			break
		}
		time.Sleep(500 * time.Millisecond)
	}

	if !jobAppeared {
		log.Println("ℹ️ Queue is empty (printer might have processed the job immediately).")
		return
	}

	// Step 2: Wait until the queue is completely clear (len(jobs) == 0)
	startTime := time.Now()
	lastAlertTime := time.Now()

	for {
		time.Sleep(1 * time.Second)

		jobs, err := p.Jobs()
		if err != nil {
			// If connection to printer is lost during printing, keep waiting
			continue
		}

		// Count the number of active print jobs (not in deleting/deleted state)
		activeJobsCount := 0
		for _, job := range jobs {
			statusLower := strings.ToLower(job.Status)
			isDeleting := (job.StatusCode&0x00000004 != 0) || // JOB_STATUS_DELETING
				(job.StatusCode&0x00000100 != 0) || // JOB_STATUS_DELETED
				strings.Contains(statusLower, "deleting") ||
				strings.Contains(statusLower, "deleted")

			if !isDeleting {
				activeJobsCount++
			}
		}

		// If there are no active jobs = Print completed (or job successfully cancelled)
		if activeJobsCount == 0 {
			log.Println("✓ Printer queue has been cleared.")
			return
		}

		// Check if there are any erroneous jobs in the queue
		var hasErrorJob bool
		var errorJobID uint32
		var errorJobDoc string
		var errorJobStatus string

		for _, job := range jobs {
			statusLower := strings.ToLower(job.Status)
			isErr := (job.StatusCode&0x00000002 != 0) || // JOB_STATUS_ERROR
				(job.StatusCode&0x00000020 != 0) || // JOB_STATUS_OFFLINE
				(job.StatusCode&0x00000040 != 0) || // JOB_STATUS_PAPEROUT
				(job.StatusCode&0x00000200 != 0) || // JOB_STATUS_BLOCKED_DEVQ
				(job.StatusCode&0x00000400 != 0) || // JOB_STATUS_USER_INTERVENTION
				strings.Contains(statusLower, "error") ||
				strings.Contains(statusLower, "offline") ||
				strings.Contains(statusLower, "paper")

			if isErr {
				hasErrorJob = true
				errorJobID = job.JobID
				errorJobDoc = job.DocumentName
				if job.Status != "" {
					errorJobStatus = job.Status
				} else {
					errorJobStatus = fmt.Sprintf("Code:0x%x", job.StatusCode)
				}
				break
			}
		}

		if hasErrorJob {
			// EVERY 1 MINUTE IF A JOB FAILS: Cancel the failed job and resend the file
			if time.Since(lastAlertTime) > 1*time.Minute {
				log.Printf("🚨 WARNING: Detected failed Job #%d '%s' (%s). Cancelling and resending...\n", errorJobID, errorJobDoc, errorJobStatus)

				// 1. Cancel the failed job in Windows Spooler
				cmdStr := fmt.Sprintf(`Remove-PrintJob -PrinterName "%s" -ID %d`, printerName, errorJobID)
				cmd := exec.Command("powershell", "-Command", cmdStr)
				cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
				if err := cmd.Run(); err != nil {
					log.Printf("⚠️ Error sending command to cancel failed job: %v\n", err)
				} else {
					log.Printf("✓ Sent command to cancel failed job #%d on Windows.\n", errorJobID)
				}

				// Wait 2 seconds for the Spooler to update
				time.Sleep(2 * time.Second)

				// 2. Send a new print command
				log.Printf("➔ Resending print command for file: %s\n", filepath.Base(filePath))
				if err := printFile(filePath, printerName); err != nil {
					log.Printf("❌ Error resending print command for file %s: %v\n", filepath.Base(filePath), err)
				}

				lastAlertTime = time.Now() // Reset warning/retry timer
			}
		} else {
			// EVERY 1 MINUTE IF THE PRINTER IS STILL JAMMED (normally busy, no error reported): Trigger warning
			if time.Since(startTime) > 1*time.Minute && time.Since(lastAlertTime) > 1*time.Minute {
				log.Printf("🚨 WARNING: Printer has been busy with %d jobs for over 1 minute. Please check paper/printer status!\n", activeJobsCount)
				lastAlertTime = time.Now() // Reset warning timer
			}
		}
	}
}

func waitForFileRelease(filePath string, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		file, err := os.OpenFile(filePath, os.O_RDWR, 0)
		if err == nil {
			file.Close()
			return true
		}
		time.Sleep(300 * time.Millisecond)
	}
	return false
}
