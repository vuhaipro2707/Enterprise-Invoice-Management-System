package print

import (
	"database/sql"
	"fmt"
	"io"
	"net/http"
	"os"
	sqlc "invoice_backend/db/sqlc"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
)

type PrintHandler struct {
	Repo    *sqlc.Queries
	service *PrintService
}

func NewPrintHandler(repo *sqlc.Queries) *PrintHandler {
	return &PrintHandler{
		Repo:    repo,
		service: NewPrintService(repo),
	}
}

func (h *PrintHandler) CreatePrintJob(c *fiber.Ctx) error {
	type createPrintJobRequest struct {
		InvoiceID           *string `json:"invoiceId"`
		CustomerPriceListID *string `json:"customerPriceListId"`
		PrintType           string  `json:"printType"`
		PrintPart           *string `json:"printPart"`
		PriorityNum         *int32  `json:"priorityNum"`
	}

	var req createPrintJobRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid JSON body. Required keys: printType, invoiceId or customerPriceListId. Optional: priorityNum, printPart",
		})
	}

	// Validation
	if req.PrintType == "" || (req.InvoiceID == nil && req.CustomerPriceListID == nil) {
		return c.Status(400).JSON(fiber.Map{
			"error": "Missing required keys: printType, invoiceId or customerPriceListId, priorityNum(optional), printPart(optional)",
		})
	}

	if req.InvoiceID != nil && req.CustomerPriceListID != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Provide exactly one of invoiceId or customerPriceListId, not both",
		})
	}

	if req.PrintType != "Original" && req.PrintType != "Triplicate" {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid printType value. Must be 'Original' or 'Triplicate'",
		})
	}

	var invID *uuid.UUID
	if req.InvoiceID != nil && *req.InvoiceID != "" {
		id, err := uuid.Parse(*req.InvoiceID)
		if err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId format (must be UUID)"})
		}
		invID = &id
	}

	var cplID *uuid.UUID
	if req.CustomerPriceListID != nil && *req.CustomerPriceListID != "" {
		id, err := uuid.Parse(*req.CustomerPriceListID)
		if err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid customerPriceListId format (must be UUID)"})
		}
		cplID = &id
	}

	var pPart *string
	if invID != nil && req.PrintType == "Original" {
		if req.PrintPart == nil || *req.PrintPart == "" {
			defaultPart := "Default"
			pPart = &defaultPart
		} else {
			pPart = req.PrintPart
			if *pPart != "A" && *pPart != "B" && *pPart != "C" && *pPart != "Default" {
				return c.Status(400).JSON(fiber.Map{
					"error": "Invalid printPart value. Must be 'A', 'B', 'C', or 'Default'",
				})
			}
		}
	}

	job, err := h.service.CreatePrintJob(c.Context(), invID, cplID, req.PrintType, pPart, req.PriorityNum)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Print job created successfully",
		"data":    flattenPrintJob(job),
	})
}

func (h *PrintHandler) GetPrintJobs(c *fiber.Ctx) error {
	var status *string
	if val := c.Query("status"); val != "" {
		status = &val
	}
	var queueType *string
	if val := c.Query("queueType"); val != "" {
		queueType = &val
	}

	var invID *uuid.UUID
	if val := c.Query("invoiceId"); val != "" {
		id, err := uuid.Parse(val)
		if err == nil {
			invID = &id
		}
	}

	var cplID *uuid.UUID
	if val := c.Query("customerPriceListId"); val != "" {
		id, err := uuid.Parse(val)
		if err == nil {
			cplID = &id
		}
	}

	limit := int32(50) // Default limit
	if val := c.Query("limit"); val != "" {
		if l, err := strconv.Atoi(val); err == nil && l > 0 {
			limit = int32(l)
		}
	}
	offset := int32(0) // Default offset
	if val := c.Query("offset"); val != "" {
		if o, err := strconv.Atoi(val); err == nil && o >= 0 {
			offset = int32(o)
		}
	}

	jobs, err := h.service.GetPrintJobs(c.Context(), status, queueType, invID, cplID, limit, offset)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	result := make([]fiber.Map, len(jobs))
	for i, j := range jobs {
		result[i] = flattenPrintJobsRow(j)
	}

	return c.Status(200).JSON(fiber.Map{
		"data": result,
	})
}

func (h *PrintHandler) PollPrintJob(c *fiber.Ctx) error {
	job, err := h.service.PollPrintJob(c.Context())
	if err != nil {
		if err == sql.ErrNoRows {
			return c.Status(404).JSON(fiber.Map{"error": "No pending print job in queue"})
		}
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	// Automatically mark polled job as 'Printing'
	status := "Printing"
	updated, err := h.service.UpdatePrintJobStatus(c.Context(), job.PrintJobID, &status, nil, nil)
	if err != nil {
		// If update fails, just return the job but log it or return error
		return c.Status(200).JSON(flattenPrintJob(job))
	}

	return c.Status(200).JSON(flattenPrintJob(updated))
}

func (h *PrintHandler) UpdatePrintJobStatus(c *fiber.Ctx) error {
	jobIDStr := c.Params("printJobId")
	if jobIDStr == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path parameter: printJobId"})
	}

	jobID, err := uuid.Parse(jobIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid printJobId format"})
	}

	type updateStatusRequest struct {
		PrintStatus *string `json:"status"`
		RetryCount  *int32  `json:"retryCount"`
		PriorityNum *int32  `json:"priorityNum"`
	}

	var req updateStatusRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid JSON body. Optional keys: status, retryCount, priorityNum",
		})
	}

	if req.PrintStatus == nil && req.PriorityNum == nil && req.RetryCount == nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Provide at least one of status, retryCount, or priorityNum to update",
		})
	}

	if req.PrintStatus != nil && *req.PrintStatus != "Pending" && *req.PrintStatus != "Printing" && *req.PrintStatus != "Completed" && *req.PrintStatus != "Failed" && *req.PrintStatus != "Cancelled" {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid status value. Must be 'Pending', 'Printing', 'Completed', 'Failed', or 'Cancelled'",
		})
	}

	updated, err := h.service.UpdatePrintJobStatus(c.Context(), jobID, req.PrintStatus, req.RetryCount, req.PriorityNum)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Print job status updated successfully",
		"data":    flattenPrintJob(updated),
	})
}

func (h *PrintHandler) PollAllQueue(c *fiber.Ctx) error {
	type pollAllRequest struct {
		IncludePrinting bool   `json:"includePrinting"`
		CompleteJobs    bool   `json:"completeJobs"`
		AfterJobID      string `json:"afterJobId"`
	}

	var req pollAllRequest
	_ = c.BodyParser(&req)

	includePrinting := req.IncludePrinting || c.QueryBool("includePrinting", false)
	completeJobs := req.CompleteJobs || c.QueryBool("completeJobs", false)
	afterJobIDStr := req.AfterJobID
	if afterJobIDStr == "" {
		afterJobIDStr = c.Query("afterJobId")
	}

	var pdfBytes []byte
	var jobCount int
	var err error

	if afterJobIDStr != "" {
		afterJobID, parseErr := uuid.Parse(afterJobIDStr)
		if parseErr != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid afterJobId UUID format"})
		}
		pdfBytes, jobCount, err = h.service.PollAllQueueAfterJob(c.Context(), afterJobID, includePrinting, completeJobs)
	} else {
		pdfBytes, jobCount, err = h.service.PollAllQueue(c.Context(), includePrinting, completeJobs)
	}

	if err != nil {
		if err == sql.ErrNoRows {
			return c.Status(404).JSON(fiber.Map{"error": "No jobs in queue to poll"})
		}
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	fileName := fmt.Sprintf("Poll_Print_Jobs_%s.pdf", time.Now().Format("20060102_150405"))
	c.Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", fileName))
	c.Set("Content-Type", "application/pdf")
	c.Set("Content-Length", fmt.Sprintf("%d", len(pdfBytes)))
	c.Set("X-Polled-Jobs-Count", fmt.Sprintf("%d", jobCount))

	return c.Send(pdfBytes)
}


func enumToString(val interface{}) string {
	if val == nil {
		return ""
	}
	switch v := val.(type) {
	case string:
		return v
	case []byte:
		return string(v)
	}
	return fmt.Sprintf("%v", val)
}

func flattenPrintJob(job sqlc.PrintQueue) fiber.Map {
	var printedAt *string
	if job.PrintedAt.Valid {
		s := job.PrintedAt.Time.Format(time.RFC3339)
		printedAt = &s
	}
	var createdAt *string
	if job.CreatedAt.Valid {
		s := job.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var invID *string
	if job.InvoiceID.Valid {
		s := job.InvoiceID.UUID.String()
		invID = &s
	}
	var cplID *string
	if job.CustomerPriceListID.Valid {
		s := job.CustomerPriceListID.UUID.String()
		cplID = &s
	}

	return fiber.Map{
		"printJobId":          job.PrintJobID,
		"invoiceId":           invID,
		"customerPriceListId": cplID,
		"printStatus":         enumToString(job.PrintStatus),
		"printType":           enumToString(job.PrintType),
		"printPart":           enumToString(job.PrintPart),
		"retryCount":          job.RetryCount.Int32,
		"priorityNum":         job.PriorityNum.Int32,
		"createdAt":            createdAt,
		"printedAt":            printedAt,
	}
}

func flattenPrintJobsRow(row sqlc.GetPrintJobsRow) fiber.Map {
	var printedAt *string
	if row.PrintedAt.Valid {
		s := row.PrintedAt.Time.Format(time.RFC3339)
		printedAt = &s
	}
	var createdAt *string
	if row.CreatedAt.Valid {
		s := row.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var invID *string
	if row.InvoiceID.Valid {
		s := row.InvoiceID.UUID.String()
		invID = &s
	}
	var cplID *string
	if row.CustomerPriceListID.Valid {
		s := row.CustomerPriceListID.UUID.String()
		cplID = &s
	}
	var invCode *string
	if row.InvoiceCode.Valid {
		invCode = &row.InvoiceCode.String
	}
	var invBuyerName *string
	if row.InvoiceBuyerName.Valid {
		invBuyerName = &row.InvoiceBuyerName.String
	}
	var priceListDesc *string
	if row.PriceListDescription.Valid {
		priceListDesc = &row.PriceListDescription.String
	}
	var priceListBuyerName *string
	if row.PriceListBuyerName.Valid {
		priceListBuyerName = &row.PriceListBuyerName.String
	}

	return fiber.Map{
		"printJobId":           row.PrintJobID,
		"invoiceId":            invID,
		"customerPriceListId":  cplID,
		"printStatus":          enumToString(row.PrintStatus),
		"printType":            enumToString(row.PrintType),
		"printPart":            enumToString(row.PrintPart),
		"retryCount":           row.RetryCount.Int32,
		"priorityNum":          row.PriorityNum.Int32,
		"createdAt":             createdAt,
		"printedAt":             printedAt,
		"invoiceCode":          invCode,
		"invoiceBuyerName":     invBuyerName,
		"priceListDescription": priceListDesc,
		"priceListBuyerName":   priceListBuyerName,
	}
}

func (h *PrintHandler) GetPrinterInfo(c *fiber.Ctx) error {
	ip := c.Query("ip")
	if ip == "" {
		ip = os.Getenv("PRINTER_IP")
	}
	if ip == "" {
		return c.Status(400).JSON(fiber.Map{
			"error": "Missing printer IP. Configure PRINTER_IP in backend env or provide ?ip= query parameter",
		})
	}

	url := fmt.Sprintf("http://%s/general/information.html", ip)

	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	req, err := http.NewRequestWithContext(c.Context(), "GET", url, nil)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to create request: %v", err),
		})
	}

	resp, err := client.Do(req)
	if err != nil {
		return c.Status(502).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to connect to printer at %s: %v", ip, err),
		})
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return c.Status(resp.StatusCode).JSON(fiber.Map{
			"error": fmt.Sprintf("Printer returned status: %s", resp.Status),
		})
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to read printer response: %v", err),
		})
	}

	// Check if there is any printing job stuck for more than 30 seconds
	isStuck := "false"
	latestJob, err := h.Repo.GetLatestPrintingJob(c.Context())
	if err == nil && latestJob.StartedPrintingAt.Valid {
		if time.Since(latestJob.StartedPrintingAt.Time) > 30*time.Second {
			isStuck = "true"
		}
	}

	c.Set("Content-Type", "text/html; charset=iso-8859-1")
	c.Set("X-Printer-IP", ip)
	c.Set("X-Printing-Stuck", isStuck)
	return c.SendString(string(bodyBytes))
}


