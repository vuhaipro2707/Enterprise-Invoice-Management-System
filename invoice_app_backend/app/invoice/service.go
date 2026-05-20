package invoice

import (
	"context"
	"database/sql"
	"fmt"
	sqlc "invoice_backend/db/sqlc"
	"os"
	"time"

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

func (s *InvoiceService) GetGoogleMapsAPIKey() string {
	return os.Getenv("GOOGLE_MAPS_API_KEY")
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

func (s *InvoiceService) GetInvoiceByID(ctx context.Context, id uuid.UUID) (sqlc.GetInvoiceByIDRow, error) {
	return s.Repo.GetInvoiceByID(ctx, id)
}

func (s *InvoiceService) GetInvoiceWithLines(ctx context.Context, id uuid.UUID) (sqlc.GetInvoiceWithLinesRow, error) {
	return s.Repo.GetInvoiceWithLines(ctx, id)
}

func (s *InvoiceService) CreateBuyer(ctx context.Context, code, name string, address, phone, idCard *string, lat, lng *float64) (sqlc.Buyer, error) {
	arg := sqlc.CreateBuyerParams{
		BuyerCode:    code,
		BuyerName:    name,
		Address:      sql.NullString{String: getString(address), Valid: address != nil},
		PhoneNumber:  sql.NullString{String: getString(phone), Valid: phone != nil},
		IDCardNumber: sql.NullString{String: getString(idCard), Valid: idCard != nil},
		Lat:          sql.NullFloat64{Float64: getFloat64(lat), Valid: lat != nil},
		Lng:          sql.NullFloat64{Float64: getFloat64(lng), Valid: lng != nil},
	}
	return s.Repo.CreateBuyer(ctx, arg)
}

func getFloat64(f *float64) float64 {
	if f == nil {
		return 0
	}
	return *f
}

func (s *InvoiceService) CreateInvoice(ctx context.Context, accountID uuid.UUID, buyerID uuid.NullUUID, code string, total int64, deviceID string, editStatus bool, buyerSnap, addrSnap, phoneSnap *string, latSnap, lngSnap *float64) (sqlc.Invoice, error) {
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
		LatSnapshot:         sql.NullFloat64{Float64: getFloat64(latSnap), Valid: latSnap != nil},
		LngSnapshot:         sql.NullFloat64{Float64: getFloat64(lngSnap), Valid: lngSnap != nil},
	}
	return s.Repo.CreateInvoice(ctx, arg)
}

func (s *InvoiceService) CreateLineItem(ctx context.Context, invoiceID, itemID, unitID uuid.UUID, qty int32, price *int64, subTotal int64, itemSnap, unitSnap string, posKey string) (sqlc.LineItem, error) {
	arg := sqlc.CreateLineItemParams{
		InvoiceID:        uuid.NullUUID{UUID: invoiceID, Valid: true},
		ItemID:           uuid.NullUUID{UUID: itemID, Valid: itemID != uuid.Nil},
		UnitID:           uuid.NullUUID{UUID: unitID, Valid: unitID != uuid.Nil},
		Quantity:         qty,
		UnitPriceCustom:  sql.NullInt64{Int64: getInt64(price), Valid: price != nil},
		SubTotal:         subTotal,
		ItemNameSnapshot: sql.NullString{String: itemSnap, Valid: itemSnap != ""},
		UnitNameSnapshot: sql.NullString{String: unitSnap, Valid: unitSnap != ""},
		PositionKey:      posKey,
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

func (s *InvoiceService) GetBuyerByCode(ctx context.Context, code string) (sqlc.Buyer, error) {
	return s.Repo.GetBuyerByCode(ctx, code)
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

func (s *InvoiceService) GetLastBuyerCode(ctx context.Context) (string, error) {
	return s.Repo.GetLastBuyerCode(ctx)
}

func (s *InvoiceService) GetLastInvoiceCode(ctx context.Context, pattern string) (string, error) {
	return s.Repo.GetLastInvoiceCode(ctx, pattern)
}

func (s *InvoiceService) GetNextBuyerCodeInternal(ctx context.Context) string {
	lastCode, err := s.GetLastBuyerCode(ctx)
	if err != nil {
		return "KH-001"
	}

	var num int
	_, err = fmt.Sscanf(lastCode, "KH-%d", &num)
	if err != nil {
		return "KH-001"
	}

	return fmt.Sprintf("KH-%03d", num+1)
}

func (s *InvoiceService) GetNextInvoiceCodeInternal(ctx context.Context) string {
	loc, _ := time.LoadLocation("Asia/Ho_Chi_Minh")
	now := time.Now().In(loc)
	prefix := fmt.Sprintf("INV-%02d%02d%02d-", now.Year()%100, now.Month(), now.Day())
	pattern := prefix + "%"

	lastCode, err := s.GetLastInvoiceCode(ctx, pattern)
	if err != nil {
		return prefix + "001"
	}

	var num int
	_, err = fmt.Sscanf(lastCode, prefix+"%d", &num)
	if err != nil {
		return prefix + "001"
	}

	return fmt.Sprintf("%s%03d", prefix, num+1)
}

func (s *InvoiceService) ListEditingInvoices(ctx context.Context) ([]sqlc.ListEditingInvoicesRow, error) {
	return s.Repo.ListEditingInvoices(ctx)
}

func (s *InvoiceService) ListBuyers(ctx context.Context, limit, offset int32) ([]sqlc.Buyer, error) {
	return s.Repo.ListBuyers(ctx, sqlc.ListBuyersParams{
		Limit:  limit,
		Offset: offset,
	})
}

func (s *InvoiceService) SearchBuyers(ctx context.Context, keyword string, limit int32) ([]sqlc.Buyer, error) {
	return s.Repo.SearchBuyers(ctx, sqlc.SearchBuyersParams{
		Keyword: keyword,
		Limit:   limit,
	})
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
	Lat             sql.NullFloat64
	SetLat          bool
	Lng             sql.NullFloat64
	SetLng          bool
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
	if input.SetLat {
		buyer.Lat = input.Lat
	}
	if input.SetLng {
		buyer.Lng = input.Lng
	}

	return s.Repo.UpdateBuyer(ctx, sqlc.UpdateBuyerParams{
		BuyerID:      buyer.BuyerID,
		BuyerCode:    buyer.BuyerCode,
		BuyerName:    buyer.BuyerName,
		Address:      buyer.Address,
		PhoneNumber:  buyer.PhoneNumber,
		IDCardNumber: buyer.IDCardNumber,
		Lat:          buyer.Lat,
		Lng:          buyer.Lng,
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
	LatSnapshot            sql.NullFloat64
	SetLatSnapshot         bool
	LngSnapshot            sql.NullFloat64
	SetLngSnapshot         bool
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
	if input.SetLatSnapshot {
		invoice.LatSnapshot = input.LatSnapshot
	}
	if input.SetLngSnapshot {
		invoice.LngSnapshot = input.LngSnapshot
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
		LatSnapshot:         invoice.LatSnapshot,
		LngSnapshot:         invoice.LngSnapshot,
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

func (s *InvoiceService) GetLineItemByID(ctx context.Context, id uuid.UUID) (sqlc.LineItem, error) {
	return s.Repo.GetLineItemByID(ctx, id)
}

func (s *InvoiceService) DeleteLineItem(ctx context.Context, id uuid.UUID) error {
	return s.Repo.DeleteLineItem(ctx, id)
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

func getFloat(f *float64) float64 {
	if f == nil {
		return 0
	}
	return *f
}

func getInt64(i *int64) int64 {
	if i == nil {
		return 0
	}
	return *i
}

func (s *InvoiceService) ListInvoicesFiltered(ctx context.Context, showEditing bool, buyerID *uuid.UUID, invoiceCode string, itemID *uuid.UUID, startDate *time.Time, endDate *time.Time, limit int32, offset int32, sortBy string, sortOrder string) ([]sqlc.ListInvoicesFilteredRow, error) {
	params := sqlc.ListInvoicesFilteredParams{
		ShowEditing: showEditing,
		LimitVal:    limit,
		OffsetVal:   offset,
		SortBy:      sortBy,
		SortOrder:   sortOrder,
	}
	if buyerID != nil {
		params.BuyerID = uuid.NullUUID{UUID: *buyerID, Valid: true}
	}
	if invoiceCode != "" {
		params.InvoiceCode = sql.NullString{String: invoiceCode, Valid: true}
	}
	if itemID != nil {
		params.ItemID = uuid.NullUUID{UUID: *itemID, Valid: true}
	}
	if startDate != nil {
		params.StartDate = sql.NullTime{Time: *startDate, Valid: true}
	}
	if endDate != nil {
		params.EndDate = sql.NullTime{Time: *endDate, Valid: true}
	}
	return s.Repo.ListInvoicesFiltered(ctx, params)
}
