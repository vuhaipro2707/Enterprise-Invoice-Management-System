package print

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"invoice_backend/app/dbconn"
	invoicePkg "invoice_backend/app/invoice"
	pricelistPkg "invoice_backend/app/pricelist"
	sqlc "invoice_backend/db/sqlc"

	"github.com/google/uuid"
	"github.com/pdfcpu/pdfcpu/pkg/api"
)

type PrintService struct {
	Repo *sqlc.Queries
}

func NewPrintService(repo *sqlc.Queries) *PrintService {
	return &PrintService{
		Repo: repo,
	}
}

func (s *PrintService) CreatePrintJob(ctx context.Context, invoiceID, customerPriceListID *uuid.UUID, printType string, printPart *string, priority *int32) (sqlc.PrintQueue, error) {
	var invID uuid.NullUUID
	if invoiceID != nil {
		invID = uuid.NullUUID{UUID: *invoiceID, Valid: true}
	}
	var cplID uuid.NullUUID
	if customerPriceListID != nil {
		cplID = uuid.NullUUID{UUID: *customerPriceListID, Valid: true}
	}

	var prio sql.NullInt32
	if priority != nil {
		prio = sql.NullInt32{Int32: *priority, Valid: true}
	}

	var pPart interface{}
	if printPart != nil && *printPart != "" {
		pPart = *printPart
	}

	arg := sqlc.CreatePrintJobParams{
		InvoiceID:           invID,
		CustomerPriceListID: cplID,
		PrintType:           printType,
		PrintPart:           pPart,
		PriorityNum:         prio,
	}

	return s.Repo.CreatePrintJob(ctx, arg)
}

func (s *PrintService) GetPrintJobs(ctx context.Context, printStatus, queueType *string, invoiceID, customerPriceListID *uuid.UUID, limit, offset int32) ([]sqlc.GetPrintJobsRow, error) {
	var status sql.NullString
	if printStatus != nil && *printStatus != "" {
		status = sql.NullString{String: *printStatus, Valid: true}
	}
	var qType sql.NullString
	if queueType != nil && *queueType != "" {
		qType = sql.NullString{String: *queueType, Valid: true}
	}
	var invID uuid.NullUUID
	if invoiceID != nil {
		invID = uuid.NullUUID{UUID: *invoiceID, Valid: true}
	}
	var cplID uuid.NullUUID
	if customerPriceListID != nil {
		cplID = uuid.NullUUID{UUID: *customerPriceListID, Valid: true}
	}

	arg := sqlc.GetPrintJobsParams{
		PrintStatus:         status,
		QueueType:           qType,
		InvoiceID:           invID,
		CustomerPriceListID: cplID,
		LimitVal:            limit,
		OffsetVal:           offset,
	}

	return s.Repo.GetPrintJobs(ctx, arg)
}

func (s *PrintService) PollPrintJob(ctx context.Context) (sqlc.PrintQueue, error) {
	return s.Repo.PollPrintJob(ctx)
}

func (s *PrintService) UpdatePrintJobStatus(ctx context.Context, printJobID uuid.UUID, status *string, retryCount, priorityNum *int32) (sqlc.PrintQueue, error) {
	var retCount sql.NullInt32
	if retryCount != nil {
		retCount = sql.NullInt32{Int32: *retryCount, Valid: true}
	}
	var prioNum sql.NullInt32
	if priorityNum != nil {
		prioNum = sql.NullInt32{Int32: *priorityNum, Valid: true}
	}

	var prStatus interface{}
	if status != nil && *status != "" {
		prStatus = *status
	}

	arg := sqlc.UpdatePrintJobStatusParams{
		PrintJobID:  printJobID,
		PrintStatus: prStatus,
		RetryCount:  retCount,
		PriorityNum: prioNum,
	}

	return s.Repo.UpdatePrintJobStatus(ctx, arg)
}

func (s *PrintService) PollAllQueue(ctx context.Context, includePrinting, completeJobs bool) ([]byte, int, error) {
	// 1. Fetch Pending jobs
	statusPending := "Pending"
	pendingJobs, err := s.GetPrintJobs(ctx, &statusPending, nil, nil, nil, 1000, 0)
	if err != nil {
		return nil, 0, err
	}

	// 2. Fetch Printing jobs if requested
	var printingJobs []sqlc.GetPrintJobsRow
	if includePrinting {
		statusPrinting := "Printing"
		printingJobs, err = s.GetPrintJobs(ctx, &statusPrinting, nil, nil, nil, 1000, 0)
		if err != nil {
			return nil, 0, err
		}
	}

	// Merge lists
	allJobs := append(pendingJobs, printingJobs...)

	if len(allJobs) == 0 {
		return nil, 0, sql.ErrNoRows
	}

	var pdfSlices [][]byte

	// 3. Generate individual PDF document bytes for each print job
	for _, job := range allJobs {
		if job.InvoiceID.Valid {
			invoice, err := s.Repo.GetInvoiceWithLines(ctx, job.InvoiceID.UUID)
			if err != nil {
				continue // Skip failed fetches gracefully
			}

			var lineItems []interface{}
			if invoice.LineItems != nil {
				json.Unmarshal(invoice.LineItems, &lineItems)
			}

			invData := map[string]interface{}{
				"invoiceId":            invoice.InvoiceID.String(),
				"invoiceCode":          invoice.InvoiceCode,
				"totalAmount":          invoice.TotalAmount,
				"buyerNameSnapshot":    "",
				"addressSnapshot":      "",
				"phoneNumberSnapshot":  "",
				"lineItems":            lineItems,
			}

			if invoice.BuyerNameSnapshot.Valid {
				invData["buyerNameSnapshot"] = invoice.BuyerNameSnapshot.String
			}
			if invoice.AddressSnapshot.Valid {
				invData["addressSnapshot"] = invoice.AddressSnapshot.String
			}
			if invoice.PhoneNumberSnapshot.Valid {
				invData["phoneNumberSnapshot"] = invoice.PhoneNumberSnapshot.String
			}

			printType := enumToString(job.PrintType)
			printPart := enumToString(job.PrintPart)
			if printType == "" {
				printType = "Original"
			}

			pdfBytes, err := invoicePkg.GenerateInvoicePDF(invData, printType, printPart)
			if err == nil && len(pdfBytes) > 0 {
				pdfSlices = append(pdfSlices, pdfBytes)
			}
		} else if job.CustomerPriceListID.Valid {
			row, err := s.Repo.GetCustomerPriceListByID(ctx, job.CustomerPriceListID.UUID)
			if err != nil {
				continue // Skip failed fetches gracefully
			}

			var buyerID *uuid.UUID
			if row.BuyerID.Valid {
				buyerID = &row.BuyerID.UUID
			}
			var isActive *bool
			if row.IsActive.Valid {
				isActive = &row.IsActive.Bool
			}
			var createdAt *string
			if row.CreatedAt.Valid {
				sTime := row.CreatedAt.Time.Format(time.RFC3339)
				createdAt = &sTime
			}
			var updatedAt *string
			if row.UpdatedAt.Valid {
				sTime := row.UpdatedAt.Time.Format(time.RFC3339)
				updatedAt = &sTime
			}
			var deletedAt *string
			if row.DeletedAt.Valid {
				sTime := row.DeletedAt.Time.Format(time.RFC3339)
				deletedAt = &sTime
			}
			var buyerCode *string
			if row.BuyerCode.Valid {
				buyerCode = &row.BuyerCode.String
			}
			var buyerName *string
			if row.BuyerName.Valid {
				buyerName = &row.BuyerName.String
			}
			var phoneNumber *string
			if row.PhoneNumber.Valid {
				phoneNumber = &row.PhoneNumber.String
			}
			var address *string
			if row.Address.Valid {
				address = &row.Address.String
			}
			var itemPrices []interface{}
			if row.ItemPrices != nil {
				json.Unmarshal(row.ItemPrices, &itemPrices)
			}

			plData := map[string]interface{}{
				"customerPriceListId": row.CustomerPriceListID,
				"description":         row.Description,
				"buyerId":             buyerID,
				"isActive":            isActive,
				"createdAt":           createdAt,
				"updatedAt":           updatedAt,
				"deletedAt":           deletedAt,
				"buyerCode":           buyerCode,
				"buyerName":           buyerName,
				"phoneNumber":         phoneNumber,
				"address":             address,
				"itemPrices":          itemPrices,
			}

			// Fetch company settings dynamically
			companyName := "Công ty Hải Minh"
			companyPhone := "0909090909"
			settings, errSettings := s.Repo.GetGlobalSettings(ctx)
			if errSettings == nil {
				var configMap map[string]interface{}
				if errJson := json.Unmarshal(settings.GlobalSettingsFile, &configMap); errJson == nil {
					if name, ok := configMap["company_name"].(string); ok && name != "" {
						companyName = name
					}
					if phone, ok := configMap["phone_number"].(string); ok && phone != "" {
						companyPhone = phone
					}
				}
			}
			plData["companyName"] = companyName
			plData["companyPhone"] = companyPhone

			pdfBytes, err := pricelistPkg.GeneratePriceListPDF(plData, "A5")
			if err == nil && len(pdfBytes) > 0 {
				pdfSlices = append(pdfSlices, pdfBytes)
			}
		}
	}

	if len(pdfSlices) == 0 {
		return nil, 0, fmt.Errorf("failed to generate PDF documents for any jobs in queue")
	}

	// 4. Merge all generated PDF documents into a single PDF
	readers := make([]io.ReadSeeker, len(pdfSlices))
	for i, slice := range pdfSlices {
		readers[i] = bytes.NewReader(slice)
	}

	var outBuf bytes.Buffer
	err = api.MergeRaw(readers, &outBuf, false, nil)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to merge PDF pages: %w", err)
	}

	// 5. If completeJobs is true, update the status inside a database transaction
	if completeJobs && len(allJobs) > 0 {
		tx, err := dbconn.DB.BeginTx(ctx, nil)
		if err != nil {
			return nil, 0, err
		}
		defer tx.Rollback()

		qTx := s.Repo.WithTx(tx)

		completedStatus := "Completed"
		for _, job := range allJobs {
			arg := sqlc.UpdatePrintJobStatusParams{
				PrintJobID:  job.PrintJobID,
				PrintStatus: completedStatus,
				RetryCount:  sql.NullInt32{Int32: job.RetryCount.Int32, Valid: true},
				PriorityNum: sql.NullInt32{Int32: job.PriorityNum.Int32, Valid: true},
			}
			_, err := qTx.UpdatePrintJobStatus(ctx, arg)
			if err != nil {
				return nil, 0, err
			}
		}

		if err := tx.Commit(); err != nil {
			return nil, 0, err
		}
	}

	return outBuf.Bytes(), len(pdfSlices), nil
}

