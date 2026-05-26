package print

import (
	"context"
	"database/sql"
	sqlc "invoice_backend/db/sqlc"

	"github.com/google/uuid"
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
