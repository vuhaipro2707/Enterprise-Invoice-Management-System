package invoice

import (
	"context"
	"database/sql"
	sqlc "invoice_backend/db/sqlc"

	"github.com/google/uuid"
)

type InvoiceService struct {
	Repo *sqlc.Queries
}

func NewInvoiceService(repo *sqlc.Queries) *InvoiceService {
	return &InvoiceService{
		Repo: repo,
	}
}

func (s *InvoiceService) GetBuyerByID(ctx context.Context, id uuid.UUID) (sqlc.Buyer, error) {
	return s.Repo.GetBuyerByID(ctx, id)
}

func (s *InvoiceService) GetItemByID(ctx context.Context, id uuid.UUID) (sqlc.GetItemByIDRow, error) {
	return s.Repo.GetItemByID(ctx, id)
}

func (s *InvoiceService) GetUnitByID(ctx context.Context, id uuid.UUID) (sqlc.Unit, error) {
	return s.Repo.GetUnitByID(ctx, id)
}

func (s *InvoiceService) GetInvoiceByID(ctx context.Context, id uuid.UUID) (sqlc.Invoice, error) {
	return s.Repo.GetInvoiceByID(ctx, id)
}

func (s *InvoiceService) CreateBuyer(ctx context.Context, code, name string, address, phone, idCard *string) (sqlc.Buyer, error) {
	arg := sqlc.CreateBuyerParams{
		BuyerCode:    code,
		BuyerName:    name,
		Address:      sql.NullString{String: getString(address), Valid: address != nil},
		PhoneNumber:  sql.NullString{String: getString(phone), Valid: phone != nil},
		IDCardNumber: sql.NullString{String: getString(idCard), Valid: idCard != nil},
	}
	return s.Repo.CreateBuyer(ctx, arg)
}

func (s *InvoiceService) CreateInvoice(ctx context.Context, accountID uuid.UUID, buyerID uuid.NullUUID, code string, total int64, deviceID string, editStatus bool, buyerSnap, addrSnap, phoneSnap *string) (sqlc.Invoice, error) {
	arg := sqlc.CreateInvoiceParams{
		AccountID:           uuid.NullUUID{UUID: accountID, Valid: true},
		BuyerID:             buyerID,
		InvoiceCode:         code,
		TotalAmount:         total,
		DeviceHoldingID:     sql.NullString{String: deviceID, Valid: deviceID != ""},
		EditStatus:          sql.NullBool{Bool: editStatus, Valid: true},
		BuyerNameSnapshot:   sql.NullString{String: getString(buyerSnap), Valid: buyerSnap != nil},
		AddressSnapshot:     sql.NullString{String: getString(addrSnap), Valid: addrSnap != nil},
		PhoneNumberSnapshot: sql.NullString{String: getString(phoneSnap), Valid: phoneSnap != nil},
	}
	return s.Repo.CreateInvoice(ctx, arg)
}

func (s *InvoiceService) CreateLineItem(ctx context.Context, invoiceID, itemID, unitID uuid.UUID, qty int32, price *int64, subTotal int64, itemSnap, unitSnap string) (sqlc.LineItem, error) {
	arg := sqlc.CreateLineItemParams{
		InvoiceID:        uuid.NullUUID{UUID: invoiceID, Valid: true},
		ItemID:           uuid.NullUUID{UUID: itemID, Valid: itemID != uuid.Nil},
		UnitID:           uuid.NullUUID{UUID: unitID, Valid: unitID != uuid.Nil},
		Quantity:         qty,
		UnitPriceCustom:  sql.NullInt64{Int64: getInt64(price), Valid: price != nil},
		SubTotal:         subTotal,
		ItemNameSnapshot: sql.NullString{String: itemSnap, Valid: itemSnap != ""},
		UnitNameSnapshot: sql.NullString{String: unitSnap, Valid: unitSnap != ""},
	}
	return s.Repo.CreateLineItem(ctx, arg)
}

func (s *InvoiceService) UpdateInvoiceStatus(ctx context.Context, invoiceID uuid.UUID, deviceID string, editStatus bool) (sqlc.Invoice, error) {
	arg := sqlc.UpdateInvoiceStatusParams{
		InvoiceID:       invoiceID,
		DeviceHoldingID: sql.NullString{String: deviceID, Valid: deviceID != ""},
		EditStatus:      sql.NullBool{Bool: editStatus, Valid: true},
	}
	return s.Repo.UpdateInvoiceStatus(ctx, arg)
}

func (s *InvoiceService) RegisterDevice(ctx context.Context, deviceID, deviceName string) (sqlc.Device, error) {
	return s.Repo.CreateDevice(ctx, sqlc.CreateDeviceParams{
		DeviceHoldingID: deviceID,
		DeviceName:      sql.NullString{String: deviceName, Valid: deviceName != ""},
	})
}

func (s *InvoiceService) GetDevice(ctx context.Context, deviceID string) (sqlc.Device, error) {
	return s.Repo.GetDeviceByID(ctx, deviceID)
}

type PatchBuyerInput struct {
	BuyerCode       string
	SetBuyerCode    bool
	BuyerName       string
	SetBuyerName    bool
	Address         sql.NullString
	SetAddress      bool
	PhoneNumber     sql.NullString
	SetPhoneNumber  bool
	IDCardNumber    sql.NullString
	SetIDCardNumber bool
}

func (s *InvoiceService) PatchBuyer(ctx context.Context, id uuid.UUID, input PatchBuyerInput) (sqlc.Buyer, error) {
	buyer, err := s.Repo.GetBuyerByID(ctx, id)
	if err != nil {
		return sqlc.Buyer{}, err
	}

	if input.SetBuyerCode {
		buyer.BuyerCode = input.BuyerCode
	}
	if input.SetBuyerName {
		buyer.BuyerName = input.BuyerName
	}
	if input.SetAddress {
		buyer.Address = input.Address
	}
	if input.SetPhoneNumber {
		buyer.PhoneNumber = input.PhoneNumber
	}
	if input.SetIDCardNumber {
		buyer.IDCardNumber = input.IDCardNumber
	}

	// We need a way to update the buyer. Since I don't have UpdateBuyer in SQLC yet,
	// I should probably add it or use a generic update if available.
	// For now, I'll assume I need to add it to db/queries/invoice.sql
	return s.Repo.UpdateBuyer(ctx, sqlc.UpdateBuyerParams{
		BuyerID:      buyer.BuyerID,
		BuyerCode:    buyer.BuyerCode,
		BuyerName:    buyer.BuyerName,
		Address:      buyer.Address,
		PhoneNumber:  buyer.PhoneNumber,
		IDCardNumber: buyer.IDCardNumber,
	})
}

type PatchInvoiceInput struct {
	AccountID              uuid.NullUUID
	SetAccountID           bool
	BuyerID                uuid.NullUUID
	SetBuyerID             bool
	InvoiceCode            string
	SetInvoiceCode         bool
	DeviceHoldingID        sql.NullString
	SetDeviceHoldingID     bool
	EditStatus             sql.NullBool
	SetEditStatus          bool
	BuyerNameSnapshot      sql.NullString
	SetBuyerNameSnapshot   bool
	AddressSnapshot        sql.NullString
	SetAddressSnapshot     bool
	PhoneNumberSnapshot    sql.NullString
	SetPhoneNumberSnapshot bool
}

func (s *InvoiceService) PatchInvoice(ctx context.Context, id uuid.UUID, input PatchInvoiceInput) (sqlc.Invoice, error) {
	invoice, err := s.Repo.GetInvoiceByID(ctx, id)
	if err != nil {
		return sqlc.Invoice{}, err
	}

	if input.SetAccountID {
		invoice.AccountID = input.AccountID
	}
	if input.SetBuyerID {
		invoice.BuyerID = input.BuyerID
	}
	if input.SetInvoiceCode {
		invoice.InvoiceCode = input.InvoiceCode
	}
	if input.SetDeviceHoldingID {
		invoice.DeviceHoldingID = input.DeviceHoldingID
	}
	if input.SetEditStatus {
		invoice.EditStatus = input.EditStatus
	}
	if input.SetBuyerNameSnapshot {
		invoice.BuyerNameSnapshot = input.BuyerNameSnapshot
	}
	if input.SetAddressSnapshot {
		invoice.AddressSnapshot = input.AddressSnapshot
	}
	if input.SetPhoneNumberSnapshot {
		invoice.PhoneNumberSnapshot = input.PhoneNumberSnapshot
	}

	return s.Repo.UpdateInvoice(ctx, sqlc.UpdateInvoiceParams{
		InvoiceID:           invoice.InvoiceID,
		AccountID:           invoice.AccountID,
		BuyerID:             invoice.BuyerID,
		InvoiceCode:         invoice.InvoiceCode,
		TotalAmount:         invoice.TotalAmount, // Keep existing, trigger will override if needed
		DeviceHoldingID:     invoice.DeviceHoldingID,
		EditStatus:          invoice.EditStatus,
		BuyerNameSnapshot:   invoice.BuyerNameSnapshot,
		AddressSnapshot:     invoice.AddressSnapshot,
		PhoneNumberSnapshot: invoice.PhoneNumberSnapshot,
	})
}

type PatchLineItemInput struct {
	ItemID              uuid.NullUUID
	SetItemID           bool
	UnitID              uuid.NullUUID
	SetUnitID           bool
	Quantity            int32
	SetQuantity         bool
	UnitPriceCustom     sql.NullInt64
	SetUnitPriceCustom  bool
	ItemNameSnapshot    sql.NullString
	SetItemNameSnapshot bool
	UnitNameSnapshot    sql.NullString
	SetUnitNameSnapshot bool
}

func (s *InvoiceService) PatchLineItem(ctx context.Context, id uuid.UUID, input PatchLineItemInput) (sqlc.LineItem, error) {
	// Need a GetLineItemByID query
	lineItem, err := s.Repo.GetLineItemByID(ctx, id)
	if err != nil {
		return sqlc.LineItem{}, err
	}

	if input.SetItemID {
		lineItem.ItemID = input.ItemID
	}
	if input.SetUnitID {
		lineItem.UnitID = input.UnitID
	}
	if input.SetQuantity {
		lineItem.Quantity = input.Quantity
	}
	if input.SetUnitPriceCustom {
		lineItem.UnitPriceCustom = input.UnitPriceCustom
	}
	if input.SetItemNameSnapshot {
		lineItem.ItemNameSnapshot = input.ItemNameSnapshot
	}
	if input.SetUnitNameSnapshot {
		lineItem.UnitNameSnapshot = input.UnitNameSnapshot
	}

	return s.Repo.UpdateLineItem(ctx, sqlc.UpdateLineItemParams{
		LineItemID:       lineItem.LineItemID,
		ItemID:           lineItem.ItemID,
		UnitID:           lineItem.UnitID,
		Quantity:         lineItem.Quantity,
		UnitPriceCustom:  lineItem.UnitPriceCustom,
		SubTotal:         lineItem.SubTotal, // Trigger will handle update if quantity/price changed
		ItemNameSnapshot: lineItem.ItemNameSnapshot,
		UnitNameSnapshot: lineItem.UnitNameSnapshot,
	})
}

func getString(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func getInt64(i *int64) int64 {
	if i == nil {
		return 0
	}
	return *i
}
