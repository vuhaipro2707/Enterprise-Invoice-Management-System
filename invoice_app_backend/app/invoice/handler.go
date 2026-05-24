package invoice

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"invoice_backend/app/shared"
	sqlc "invoice_backend/db/sqlc"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
)

type InvoiceHandler struct {
	Repo    *sqlc.Queries
	service *InvoiceService
}

func NewInvoiceHandler(repo *sqlc.Queries) *InvoiceHandler {
	return &InvoiceHandler{
		Repo:    repo,
		service: NewInvoiceService(repo),
	}
}

func (h *InvoiceHandler) CreateBuyer(c *fiber.Ctx) error {
	type createBuyerRequest struct {
		BuyerCode    string   `json:"buyerCode"`
		BuyerName    string   `json:"buyerName"`
		Address      *string  `json:"address"`
		PhoneNumber  *string  `json:"phoneNumber"`
		IdCardNumber *string  `json:"idCardNumber"`
		Email        *string  `json:"email"`
		TaxId        *string  `json:"taxId"`
		Lat          *float64 `json:"lat"`
		Lng          *float64 `json:"lng"`
	}

	var req createBuyerRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required keys: buyerCode, buyerName. Optional: address, phoneNumber, idCardNumber, email, taxId, lat, lng"})
	}

	if req.BuyerCode == "" || req.BuyerName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: buyerCode, buyerName, address(optional), phoneNumber(optional), idCardNumber(optional), email(optional), taxId(optional), lat(optional), lng(optional)"})
	}

	if req.Email != nil && *req.Email != "" {
		if !isValidEmail(*req.Email) {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid email format"})
		}
	}

	if strings.HasPrefix(req.BuyerCode, "KH-") {
		next := h.service.GetNextBuyerCodeInternal(context.Background())
		if req.BuyerCode != next {
			return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Code mismatch! Next available code is %s", next)})
		}
	}

	buyer, err := h.service.CreateBuyer(context.Background(), req.BuyerCode, req.BuyerName, req.Address, req.PhoneNumber, req.IdCardNumber, req.Email, req.TaxId, req.Lat, req.Lng)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Buyer created successfully",
		"data":    flattenBuyer(buyer),
	})
}

func (h *InvoiceHandler) CreateInvoice(c *fiber.Ctx) error {
	type createInvoiceRequest struct {
		BuyerID       *string  `json:"buyerId"`
		InvoiceCode   string   `json:"invoiceCode"`
		EditStatus    bool     `json:"editStatus"`
		BuyerNameSnap *string  `json:"buyerNameSnapshot"`
		AddressSnap   *string  `json:"addressSnapshot"`
		PhoneSnap     *string  `json:"phoneNumberSnapshot"`
		IdCardSnap    *string  `json:"idCardNumberSnapshot"`
		EmailSnap     *string  `json:"emailSnapshot"`
		TaxIDSnap     *string  `json:"taxIdSnapshot"`
		LatSnap       *float64 `json:"latSnapshot"`
		LngSnap       *float64 `json:"lngSnapshot"`
	}

	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	var req createInvoiceRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required: invoiceCode. Optional: buyerId, editStatus, buyerNameSnapshot, addressSnapshot, phoneNumberSnapshot, idCardNumberSnapshot, emailSnapshot, taxIdSnapshot, latSnapshot, lngSnapshot"})
	}

	if req.InvoiceCode == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: invoiceCode, buyerId(optional), editStatus(optional), buyerNameSnapshot(optional if buyerId provided), addressSnapshot(optional), phoneNumberSnapshot(optional), idCardNumberSnapshot(optional), emailSnapshot(optional), taxIdSnapshot(optional), latSnapshot(optional), lngSnapshot(optional)"})
	}

	if req.EmailSnap != nil && *req.EmailSnap != "" {
		if !isValidEmail(*req.EmailSnap) {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid email format"})
		}
	}

	loc, _ := time.LoadLocation("Asia/Ho_Chi_Minh")
	prefix := fmt.Sprintf("INV-%02d%02d%02d-", time.Now().In(loc).Year()%100, time.Now().In(loc).Month(), time.Now().In(loc).Day())
	if strings.HasPrefix(req.InvoiceCode, prefix) {
		next := h.service.GetNextInvoiceCodeInternal(context.Background())
		if req.InvoiceCode != next {
			return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Code mismatch! Next available code is %s", next)})
		}
	}

	// Validation: If no buyerId, buyerNameSnapshot is required
	if req.BuyerID == nil && (req.BuyerNameSnap == nil || *req.BuyerNameSnap == "") {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: buyerId or buyerNameSnapshot"})
	}

	// Get username from middleware
	usernameRaw := c.Locals("username")
	if usernameRaw == nil {
		return c.Status(401).JSON(fiber.Map{"error": "Unauthorized: user not found"})
	}
	username := usernameRaw.(string)

	// Fetch account details to get AccountID
	account, err := h.Repo.GetAccountByUsername(context.Background(), username)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to retrieve account information"})
	}

	var buyID uuid.NullUUID
	if req.BuyerID != nil {
		parsedID, err := uuid.Parse(*req.BuyerID)
		if err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid buyerId (must be UUID)"})
		}
		buyID = uuid.NullUUID{UUID: parsedID, Valid: true}
	} else {
		buyID = uuid.NullUUID{Valid: false}
	}

	// Snapshot logic
	if req.BuyerID != nil && (req.BuyerNameSnap == nil || req.AddressSnap == nil || req.PhoneSnap == nil || req.IdCardSnap == nil || req.EmailSnap == nil || req.TaxIDSnap == nil || req.LatSnap == nil || req.LngSnap == nil) {
		buyer, err := h.service.GetBuyerByID(context.Background(), buyID.UUID)
		if err == nil {
			if req.BuyerNameSnap == nil {
				req.BuyerNameSnap = &buyer.BuyerName
			}
			if req.AddressSnap == nil && buyer.Address.Valid {
				req.AddressSnap = &buyer.Address.String
			}
			if req.PhoneSnap == nil && buyer.PhoneNumber.Valid {
				req.PhoneSnap = &buyer.PhoneNumber.String
			}
			if req.IdCardSnap == nil && buyer.IDCardNumber.Valid {
				req.IdCardSnap = &buyer.IDCardNumber.String
			}
			if req.EmailSnap == nil && buyer.Email.Valid {
				req.EmailSnap = &buyer.Email.String
			}
			if req.TaxIDSnap == nil && buyer.TaxID.Valid {
				req.TaxIDSnap = &buyer.TaxID.String
			}
			if req.LatSnap == nil && buyer.Lat.Valid {
				req.LatSnap = &buyer.Lat.Float64
			}
			if req.LngSnap == nil && buyer.Lng.Valid {
				req.LngSnap = &buyer.Lng.Float64
			}
		}
	}

	// TotalAmount is handled by trigger based on line items, initial is 0
	invoice, err := h.service.CreateInvoice(context.Background(), account.AccountID, buyID, req.InvoiceCode, 0, deviceHoldingID, req.EditStatus, req.BuyerNameSnap, req.AddressSnap, req.PhoneSnap, req.IdCardSnap, req.EmailSnap, req.TaxIDSnap, req.LatSnap, req.LngSnap)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to create invoice: %v", err)})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Invoice created successfully",
		"data":    flattenInvoice(invoice),
	})
}

func (h *InvoiceHandler) CreateLineItem(c *fiber.Ctx) error {
	type createLineItemRequest struct {
		ItemID           *string `json:"itemId"`
		UnitID           *string `json:"unitId"`
		Quantity         int32   `json:"quantity"`
		UnitPriceCustom  *int64  `json:"unitPriceCustom"`
		ItemNameSnapshot *string `json:"itemNameSnapshot"`
		UnitNameSnapshot *string `json:"unitNameSnapshot"`
	}

	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	invoiceIDStr := c.Params("invoiceId")
	if invoiceIDStr == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	var req createLineItemRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required: quantity. Optional: itemId, unitId, unitPriceCustom, itemNameSnapshot, unitNameSnapshot"})
	}

	if req.Quantity <= 0 {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: quantity(>0), itemId(optional if itemNameSnapshot provided), unitId(optional if unitNameSnapshot provided)"})
	}

	invID, err := uuid.Parse(invoiceIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId (must be UUID)"})
	}

	// Validation: If no itemId, itemNameSnapshot is required
	if req.ItemID == nil && (req.ItemNameSnapshot == nil || *req.ItemNameSnapshot == "") {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: itemId or itemNameSnapshot"})
	}
	// Validation: If no unitId, unitNameSnapshot and unitPriceCustom are required
	if req.UnitID == nil {
		if req.UnitNameSnapshot == nil || *req.UnitNameSnapshot == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: unitId or unitNameSnapshot"})
		}
		if req.UnitPriceCustom == nil {
			return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: unitId or unitPriceCustom"})
		}
	}
	// Validation: If unitId is provided, itemId must also be provided
	if req.UnitID != nil && req.ItemID == nil {
		return c.Status(400).JSON(fiber.Map{"error": "Cannot provide unitId without itemId"})
	}

	var itmID uuid.UUID
	if req.ItemID != nil {
		itmID, err = uuid.Parse(*req.ItemID)
		if err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid itemId (must be UUID)"})
		}
	}

	var untID uuid.UUID
	if req.UnitID != nil {
		untID, err = uuid.Parse(*req.UnitID)
		if err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid unitId (must be UUID)"})
		}
	}

	// Validation
	invoice, err := h.service.GetInvoiceByID(context.Background(), invID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
	}

	if !invoice.EditStatus.Bool || (invoice.DeviceHoldingID.Valid && invoice.DeviceHoldingID.String != deviceHoldingID) {
		return c.Status(403).JSON(fiber.Map{"error": "Invoice is not in edit mode or deviceHoldingId mismatch"})
	}

	// Validate if unitId belongs to itemId (only if both are provided)
	if req.ItemID != nil && req.UnitID != nil {
		unit, err := h.service.GetUnitByID(context.Background(), untID)
		if err != nil {
			return c.Status(404).JSON(fiber.Map{"error": "Unit not found"})
		}

		if !unit.ItemID.Valid || unit.ItemID.UUID != itmID {
			return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Unit %s does not belong to Item %s", untID, itmID)})
		}
	}

	// Snapshot logic
	if req.ItemID != nil && (req.ItemNameSnapshot == nil || *req.ItemNameSnapshot == "") {
		item, err := h.service.GetItemByID(context.Background(), itmID)
		if err == nil {
			req.ItemNameSnapshot = &item.ItemDefaultName
		}
	}
	if req.UnitID != nil && (req.UnitNameSnapshot == nil || *req.UnitNameSnapshot == "") {
		unit, err := h.service.GetUnitByID(context.Background(), untID)
		if err == nil {
			req.UnitNameSnapshot = &unit.UnitName
		}
	}
	if req.UnitID != nil && req.UnitPriceCustom == nil {
		unit, err := h.service.GetUnitByID(context.Background(), untID)
		if err == nil {
			req.UnitPriceCustom = &unit.UnitPriceDefault
		}
	}

	// Calculate positionKey (insert at end)
	invoiceWithLines, _ := h.service.Repo.GetInvoiceWithLines(context.Background(), invID)
	posKey := "i0000" // Default for the first item
	var lines []map[string]interface{}
	if invoiceWithLines.LineItems != nil {
		json.Unmarshal(invoiceWithLines.LineItems, &lines)
	}
	if len(lines) > 0 {
		lastLine := lines[len(lines)-1]
		if lastPos, ok := lastLine["positionKey"].(string); ok {
			posKey = shared.GenerateMidString(lastPos, "zzzzz")
		}
	}

	// subTotal is calculated by DB trigger, we pass 0 from app
	lineItem, err := h.service.CreateLineItem(context.Background(), invID, itmID, untID, req.Quantity, req.UnitPriceCustom, 0, getString(req.ItemNameSnapshot), getString(req.UnitNameSnapshot), posKey)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to create line item: %v", err)})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Line item created successfully",
		"data":    flattenLineItem(lineItem),
	})
}

func (h *InvoiceHandler) ChangeLineItemOrder(c *fiber.Ctx) error {
	type changeOrderRequest struct {
		PrevLineItemID *string `json:"prevLineItemId"`
		NextLineItemID *string `json:"nextLineItemId"`
		LineItemID     string  `json:"lineItemId"`
	}

	var req changeOrderRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid body"})
	}

	invoiceIDStr := c.Params("invoiceId")
	invID, err := uuid.Parse(invoiceIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId"})
	}

	targetUUID, err := uuid.Parse(req.LineItemID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid lineItemId"})
	}

	invoiceWithLines, err := h.service.Repo.GetInvoiceWithLines(context.Background(), invID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
	}

	var lines []map[string]interface{}
	json.Unmarshal(invoiceWithLines.LineItems, &lines)

	var prevKey, nextKey string
	for _, l := range lines {
		id := l["lineItemId"].(string)
		pk := l["positionKey"].(string)
		if req.PrevLineItemID != nil && *req.PrevLineItemID == id {
			prevKey = pk
		}
		if req.NextLineItemID != nil && *req.NextLineItemID == id {
			nextKey = pk
		}
	}

	newPosKey := shared.GenerateMidString(prevKey, nextKey)

	err = h.service.Repo.UpdateLineItemPos(context.Background(), sqlc.UpdateLineItemPosParams{
		LineItemID:  targetUUID,
		PositionKey: newPosKey,
	})
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Order updated", "newPositionKey": newPosKey})
}

func (h *InvoiceHandler) TakeTurn(c *fiber.Ctx) error {
	invoiceIDStr := c.Params("invoiceId")
	if invoiceIDStr == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	invID, err := uuid.Parse(invoiceIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId (must be UUID)"})
	}

	invoice, err := h.service.UpdateInvoiceStatus(context.Background(), invID, deviceHoldingID, true)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to take turn: %v", err)})
	}

	var editStatus *bool
	if invoice.EditStatus.Valid {
		editStatus = &invoice.EditStatus.Bool
	}
	var deviceHoldingIDVal *string
	if invoice.DeviceHoldingID.Valid {
		deviceHoldingIDVal = &invoice.DeviceHoldingID.String
	}
	return c.Status(200).JSON(fiber.Map{
		"message": "Took turn successfully",
		"data": fiber.Map{
			"invoiceId":       invoice.InvoiceID,
			"editStatus":      editStatus,
			"deviceHoldingId": deviceHoldingIDVal,
		},
	})
}

func (h *InvoiceHandler) Finish(c *fiber.Ctx) error {
	invoiceIDStr := c.Params("invoiceId")
	if invoiceIDStr == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	invID, err := uuid.Parse(invoiceIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId (must be UUID)"})
	}

	// Check if current device holds the invoice
	invoice, err := h.service.GetInvoiceByID(context.Background(), invID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
	}

	if !invoice.DeviceHoldingID.Valid || invoice.DeviceHoldingID.String != deviceHoldingID {
		return c.Status(403).JSON(fiber.Map{"error": "deviceHoldingId mismatch"})
	}

	updatedInvoice, err := h.service.UpdateInvoiceStatus(context.Background(), invID, deviceHoldingID, false)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to finish: %v", err)})
	}

	var editStatus *bool
	if updatedInvoice.EditStatus.Valid {
		editStatus = &updatedInvoice.EditStatus.Bool
	}
	var deviceHoldingIDVal *string
	if updatedInvoice.DeviceHoldingID.Valid {
		deviceHoldingIDVal = &updatedInvoice.DeviceHoldingID.String
	}
	return c.Status(200).JSON(fiber.Map{
		"message": "Finished successfully",
		"data": fiber.Map{
			"invoiceId":       updatedInvoice.InvoiceID,
			"editStatus":      editStatus,
			"deviceHoldingId": deviceHoldingIDVal,
		},
	})
}

func (h *InvoiceHandler) LockInvoice(c *fiber.Ctx) error {
	invoiceIDStr := c.Params("invoiceId")
	if invoiceIDStr == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	invID, err := uuid.Parse(invoiceIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId (must be UUID)"})
	}

	invoice, err := h.service.GetInvoiceByID(context.Background(), invID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
	}

	// Custom security logic:
	// Only enforce holding check if the invoice is currently in edit status (editStatus = true)
	if invoice.EditStatus.Bool {
		deviceHoldingID := c.Get("X-Device-Holding-ID")
		if deviceHoldingID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Missing header X-Device-Holding-ID"})
		}
		if !invoice.DeviceHoldingID.Valid || invoice.DeviceHoldingID.String != deviceHoldingID {
			return c.Status(403).JSON(fiber.Map{"error": "deviceHoldingId mismatch (invoice is currently being edited by another device)"})
		}
	}

	updatedInvoice, err := h.service.LockInvoice(context.Background(), invID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to lock invoice: %v", err)})
	}

	var paidLocked *bool
	if updatedInvoice.PaidLocked.Valid {
		paidLocked = &updatedInvoice.PaidLocked.Bool
	}
	var editStatus *bool
	if updatedInvoice.EditStatus.Valid {
		editStatus = &updatedInvoice.EditStatus.Bool
	}
	return c.Status(200).JSON(fiber.Map{
		"message": "Locked invoice successfully",
		"data": fiber.Map{
			"invoiceId":  updatedInvoice.InvoiceID,
			"paidLocked": paidLocked,
			"editStatus": editStatus,
		},
	})
}

func (h *InvoiceHandler) PingInvoice(c *fiber.Ctx) error {
	invoiceIDStr := c.Params("invoiceId")
	if invoiceIDStr == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	invID, err := uuid.Parse(invoiceIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid invoiceId (must be UUID)"})
	}

	invoice, err := h.Repo.GetInvoiceWithDeviceName(context.Background(), invID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
	}

	var deviceHoldingID *string
	if invoice.DeviceHoldingID.Valid {
		deviceHoldingID = &invoice.DeviceHoldingID.String
	}
	var deviceName *string
	if invoice.DeviceName.Valid {
		deviceName = &invoice.DeviceName.String
	}
	var editStatus *bool
	if invoice.EditStatus.Valid {
		editStatus = &invoice.EditStatus.Bool
	}
	var paidLocked *bool
	if invoice.PaidLocked.Valid {
		paidLocked = &invoice.PaidLocked.Bool
	}

	return c.Status(200).JSON(fiber.Map{
		"deviceHoldingId": deviceHoldingID,
		"deviceName":      deviceName,
		"editStatus":      editStatus,
		"paidLocked":      paidLocked,
	})
}

func (h *InvoiceHandler) GetBuyerByCode(c *fiber.Ctx) error {
	code := c.Query("code")
	if code == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing query param: code"})
	}

	buyer, err := h.service.GetBuyerByCode(context.Background(), code)
	if err != nil {
		if err == sql.ErrNoRows {
			return c.Status(404).JSON(fiber.Map{"error": "Buyer not found"})
		}
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to get buyer: %v", err)})
	}

	return c.Status(200).JSON(flattenBuyer(buyer))
}

func (h *InvoiceHandler) RegisterDevice(c *fiber.Ctx) error {
	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	type registerDeviceRequest struct {
		DeviceName string `json:"deviceName"`
	}

	var req registerDeviceRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required: deviceName"})
	}

	if req.DeviceName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required key: deviceName"})
	}

	device, err := h.service.RegisterDevice(context.Background(), deviceHoldingID, req.DeviceName)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to register device: %v", err)})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Device registered successfully",
		"data":    flattenDevice(device),
	})
}

func (h *InvoiceHandler) CheckRegistered(c *fiber.Ctx) error {
	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	device, err := h.service.GetDevice(context.Background(), deviceHoldingID)
	if err != nil {
		return c.Status(200).JSON(fiber.Map{
			"registered": false,
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"registered": true,
		"data":       flattenDevice(device),
	})
}

func (h *InvoiceHandler) GetNextBuyerCode(c *fiber.Ctx) error {
	nextCode := h.service.GetNextBuyerCodeInternal(context.Background())
	return c.Status(200).JSON(fiber.Map{"nextCode": nextCode})
}

func (h *InvoiceHandler) GetNextInvoiceCode(c *fiber.Ctx) error {
	nextCode := h.service.GetNextInvoiceCodeInternal(context.Background())
	return c.Status(200).JSON(fiber.Map{"nextCode": nextCode})
}

func (h *InvoiceHandler) GetInvoiceWithLines(c *fiber.Ctx) error {
	invoiceIDStr := c.Params("invoiceId")
	invoiceID, err := uuid.Parse(invoiceIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid invoice ID format"})
	}

	invoice, err := h.service.GetInvoiceWithLines(context.Background(), invoiceID)
	if err != nil {
		if err == sql.ErrNoRows {
			return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
		}
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to get invoice: %v", err)})
	}

	// Flatten the result for cleaner JSON output
	var lineItems []interface{}
	if invoice.LineItems != nil {
		json.Unmarshal(invoice.LineItems, &lineItems)
	}

	var accountID *uuid.UUID
	if invoice.AccountID.Valid {
		accountID = &invoice.AccountID.UUID
	}
	var buyerID *uuid.UUID
	if invoice.BuyerID.Valid {
		buyerID = &invoice.BuyerID.UUID
	}
	var buyerCode *string
	if invoice.BuyerCode.Valid {
		buyerCode = &invoice.BuyerCode.String
	}
	var deviceHoldingId *string
	if invoice.DeviceHoldingID.Valid {
		deviceHoldingId = &invoice.DeviceHoldingID.String
	}
	var deviceName *string
	if invoice.DeviceHoldingID.Valid {
		if dev, err := h.Repo.GetDeviceByID(context.Background(), invoice.DeviceHoldingID.String); err == nil {
			if dev.DeviceName.Valid {
				deviceName = &dev.DeviceName.String
			}
		}
	}
	var editStatus *bool
	if invoice.EditStatus.Valid {
		editStatus = &invoice.EditStatus.Bool
	}
	var paidLocked *bool
	if invoice.PaidLocked.Valid {
		paidLocked = &invoice.PaidLocked.Bool
	}
	var buyerNameSnapshot *string
	if invoice.BuyerNameSnapshot.Valid {
		buyerNameSnapshot = &invoice.BuyerNameSnapshot.String
	}
	var addressSnapshot *string
	if invoice.AddressSnapshot.Valid {
		addressSnapshot = &invoice.AddressSnapshot.String
	}
	var idCardNumberSnapshot *string
	if invoice.IDCardNumberSnapshot.Valid {
		idCardNumberSnapshot = &invoice.IDCardNumberSnapshot.String
	}
	var emailSnapshot *string
	if invoice.EmailSnapshot.Valid {
		emailSnapshot = &invoice.EmailSnapshot.String
	}
	var latSnapshot *float64
	if invoice.LatSnapshot.Valid {
		latSnapshot = &invoice.LatSnapshot.Float64
	}
	var lngSnapshot *float64
	if invoice.LngSnapshot.Valid {
		lngSnapshot = &invoice.LngSnapshot.Float64
	}
	var phoneNumberSnapshot *string
	if invoice.PhoneNumberSnapshot.Valid {
		phoneNumberSnapshot = &invoice.PhoneNumberSnapshot.String
	}
	var taxIdSnapshot *string
	if invoice.TaxIDSnapshot.Valid {
		taxIdSnapshot = &invoice.TaxIDSnapshot.String
	}
	var isActive *bool
	if invoice.IsActive.Valid {
		isActive = &invoice.IsActive.Bool
	}
	var createdAt *string
	if invoice.CreatedAt.Valid {
		s := invoice.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if invoice.UpdatedAt.Valid {
		s := invoice.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}

	res := fiber.Map{
		"invoiceId":            invoice.InvoiceID,
		"accountId":            accountID,
		"buyerId":              buyerID,
		"buyerCode":            buyerCode,
		"invoiceCode":          invoice.InvoiceCode,
		"totalAmount":          invoice.TotalAmount,
		"deviceHoldingId":      deviceHoldingId,
		"deviceName":           deviceName,
		"editStatus":           editStatus,
		"paidLocked":           paidLocked,
		"buyerNameSnapshot":    buyerNameSnapshot,
		"addressSnapshot":      addressSnapshot,
		"idCardNumberSnapshot": idCardNumberSnapshot,
		"emailSnapshot":        emailSnapshot,
		"latSnapshot":          latSnapshot,
		"lngSnapshot":          lngSnapshot,
		"phoneNumberSnapshot":  phoneNumberSnapshot,
		"taxIdSnapshot":        taxIdSnapshot,
		"isActive":             isActive,
		"createdAt":            createdAt,
		"updatedAt":            updatedAt,
		"lineItems":            lineItems,
	}

	return c.Status(200).JSON(res)
}

func (h *InvoiceHandler) GooglePlaceAutocomplete(c *fiber.Ctx) error {
	keyword := c.Query("keyword")
	sessionToken := c.Query("sessiontoken")
	if keyword == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing query param: keyword"})
	}

	apiKey := h.service.GetGoogleMapsAPIKey()
	if apiKey == "" {
		return c.Status(500).JSON(fiber.Map{"error": "Google Maps API Key not configured on server"})
	}

	reqBody := map[string]interface{}{
		"input":               keyword,
		"languageCode":        "vi",
		"includedRegionCodes": []string{"vn"},
		"locationBias": map[string]interface{}{
			"circle": map[string]interface{}{
				"center": map[string]interface{}{
					"latitude":  10.7449508,
					"longitude": 106.6506517,
				},
				"radius": 30000.0,
			},
		},
	}
	if sessionToken != "" {
		reqBody["sessionToken"] = sessionToken
	}

	agent := fiber.Post("https://places.googleapis.com/v1/places:autocomplete")
	agent.JSON(reqBody)
	agent.Set("X-Goog-Api-Key", apiKey)
	agent.Set("Content-Type", "application/json")

	statusCode, body, errs := agent.Bytes()
	if len(errs) > 0 {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to call Google API: %v", errs[0])})
	}

	if statusCode != 200 {
		return c.Status(statusCode).Send(body)
	}

	var newResult struct {
		Suggestions []struct {
			PlacePrediction struct {
				PlaceId string `json:"placeId"`
				Text    struct {
					Text string `json:"text"`
				} `json:"text"`
				StructuredFormat struct {
					MainText struct {
						Text string `json:"text"`
					} `json:"mainText"`
					SecondaryText struct {
						Text string `json:"text"`
					} `json:"secondaryText"`
				} `json:"structuredFormat"`
			} `json:"placePrediction"`
		} `json:"suggestions"`
	}

	if err := json.Unmarshal(body, &newResult); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to parse Google API response: %v", err)})
	}

	type StructuredFormatting struct {
		MainText      string `json:"main_text"`
		SecondaryText string `json:"secondary_text"`
	}
	type Prediction struct {
		Description          string               `json:"description"`
		PlaceID              string               `json:"place_id"`
		StructuredFormatting StructuredFormatting `json:"structured_formatting"`
	}

	predictions := []Prediction{}
	for _, sug := range newResult.Suggestions {
		pred := sug.PlacePrediction
		if pred.PlaceId == "" {
			continue
		}

		desc := shared.EnrichAddress(pred.Text.Text)
		mainTxt := shared.EnrichAddress(pred.StructuredFormat.MainText.Text)
		secTxt := shared.EnrichAddress(pred.StructuredFormat.SecondaryText.Text)

		predictions = append(predictions, Prediction{
			Description: desc,
			PlaceID:     pred.PlaceId,
			StructuredFormatting: StructuredFormatting{
				MainText:      mainTxt,
				SecondaryText: secTxt,
			},
		})
	}

	return c.JSON(fiber.Map{"predictions": predictions})
}

func (h *InvoiceHandler) GooglePlaceDetails(c *fiber.Ctx) error {
	placeID := c.Query("placeId")
	sessionToken := c.Query("sessiontoken")
	if placeID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing query param: placeId"})
	}

	apiKey := h.service.GetGoogleMapsAPIKey()
	if apiKey == "" {
		return c.Status(500).JSON(fiber.Map{"error": "Google Maps API Key not configured on server"})
	}

	googleUrl := fmt.Sprintf("https://places.googleapis.com/v1/places/%s", url.PathEscape(placeID))
	if sessionToken != "" {
		googleUrl += "?sessionToken=" + url.QueryEscape(sessionToken)
	}

	agent := fiber.Get(googleUrl)
	agent.Set("X-Goog-Api-Key", apiKey)
	agent.Set("X-Goog-FieldMask", "id,formattedAddress,location")

	statusCode, body, errs := agent.Bytes()
	if len(errs) > 0 {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to call Google API: %v", errs[0])})
	}

	if statusCode != 200 {
		return c.Status(statusCode).Send(body)
	}

	var newDetails struct {
		ID               string `json:"id"`
		FormattedAddress string `json:"formattedAddress"`
		Location         struct {
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
		} `json:"location"`
	}

	if err := json.Unmarshal(body, &newDetails); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to parse Google API response: %v", err)})
	}

	type LatLng struct {
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
	}
	type Geometry struct {
		Location LatLng `json:"location"`
	}
	type Result struct {
		FormattedAddress string   `json:"formatted_address"`
		Geometry         Geometry `json:"geometry"`
	}

	resp := fiber.Map{
		"status": "OK",
		"result": Result{
			FormattedAddress: shared.EnrichAddress(newDetails.FormattedAddress),
			Geometry: Geometry{
				Location: LatLng{
					Lat: newDetails.Location.Latitude,
					Lng: newDetails.Location.Longitude,
				},
			},
		},
	}

	return c.JSON(resp)
}

func (h *InvoiceHandler) GoogleReverseGeocode(c *fiber.Ctx) error {
	lat := c.Query("lat")
	lng := c.Query("lng")
	if lat == "" || lng == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing query params: lat, lng"})
	}

	apiKey := h.service.GetGoogleMapsAPIKey()
	if apiKey == "" {
		return c.Status(500).JSON(fiber.Map{"error": "Google Maps API Key not configured on server"})
	}

	googleUrl := fmt.Sprintf("https://geocode.googleapis.com/v4/geocode/location/%s,%s", url.PathEscape(lat), url.PathEscape(lng))

	agent := fiber.Get(googleUrl)
	agent.Set("X-Goog-Api-Key", apiKey)
	agent.Set("X-Goog-FieldMask", "results.formattedAddress")

	statusCode, body, errs := agent.Bytes()
	if len(errs) > 0 {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to call Google API: %v", errs[0])})
	}

	if statusCode != 200 {
		return c.Status(statusCode).Send(body)
	}

	var newResponse struct {
		Results []struct {
			FormattedAddress string `json:"formattedAddress"`
		} `json:"results"`
	}

	if err := json.Unmarshal(body, &newResponse); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to parse Google API response: %v", err)})
	}

	if len(newResponse.Results) > 0 {
		return c.JSON(fiber.Map{
			"address": shared.EnrichAddress(newResponse.Results[0].FormattedAddress),
		})
	}

	return c.Status(404).JSON(fiber.Map{"error": "No address found for these coordinates"})
}

func (h *InvoiceHandler) GoogleGeocode(c *fiber.Ctx) error {
	address := c.Query("address")
	if address == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing query param: address"})
	}

	apiKey := h.service.GetGoogleMapsAPIKey()
	if apiKey == "" {
		return c.Status(500).JSON(fiber.Map{"error": "Google Maps API Key not configured on server"})
	}

	googleUrl := fmt.Sprintf("https://geocode.googleapis.com/v4/geocode/address/%s", url.PathEscape(address))

	agent := fiber.Get(googleUrl)
	agent.Set("X-Goog-Api-Key", apiKey)
	agent.Set("X-Goog-FieldMask", "results.location")

	statusCode, body, errs := agent.Bytes()
	if len(errs) > 0 {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to call Google API: %v", errs[0])})
	}

	if statusCode != 200 {
		return c.Status(statusCode).Send(body)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to parse Google API response: %v", err)})
	}

	results, ok := result["results"].([]interface{})
	if !ok || len(results) == 0 {
		return c.Status(404).JSON(fiber.Map{"error": "No coordinates found for this address"})
	}

	firstResult, ok := results[0].(map[string]interface{})
	if !ok {
		return c.Status(404).JSON(fiber.Map{"error": "No coordinates found for this address"})
	}

	var lat, lng float64
	var found bool

	// Check direct "location" key
	if loc, ok := firstResult["location"].(map[string]interface{}); ok {
		if lt, ok := loc["latitude"].(float64); ok {
			lat = lt
			found = true
		} else if lt, ok := loc["lat"].(float64); ok {
			lat = lt
			found = true
		}
		if ln, ok := loc["longitude"].(float64); ok {
			lng = ln
		} else if ln, ok := loc["lng"].(float64); ok {
			lng = ln
		}
	}

	// Check nested "geometry.location" key
	if !found {
		if geom, ok := firstResult["geometry"].(map[string]interface{}); ok {
			if loc, ok := geom["location"].(map[string]interface{}); ok {
				if lt, ok := loc["latitude"].(float64); ok {
					lat = lt
					found = true
				} else if lt, ok := loc["lat"].(float64); ok {
					lat = lt
					found = true
				}
				if ln, ok := loc["longitude"].(float64); ok {
					lng = ln
				} else if ln, ok := loc["lng"].(float64); ok {
					lng = ln
				}
			}
		}
	}

	if !found {
		return c.Status(404).JSON(fiber.Map{"error": "Coordinates not found in response"})
	}

	return c.JSON(fiber.Map{
		"lat": lat,
		"lng": lng,
	})
}

func (h *InvoiceHandler) GetBuyers(c *fiber.Ctx) error {
	limit := c.QueryInt("limit", 20)
	offset := c.QueryInt("offset", 0)

	buyers, err := h.service.ListBuyers(context.Background(), int32(limit), int32(offset))
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to list buyers: %v", err)})
	}

	if buyers == nil {
		buyers = []sqlc.Buyer{}
	}

	resp := make([]fiber.Map, len(buyers))
	for i, b := range buyers {
		resp[i] = flattenBuyer(b)
	}

	return c.Status(200).JSON(resp)
}

func (h *InvoiceHandler) SearchBuyers(c *fiber.Ctx) error {
	keyword := c.Query("keyword")
	if keyword == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing query param: keyword"})
	}
	limit := c.QueryInt("limit", 20)

	buyers, err := h.service.SearchBuyers(context.Background(), keyword, int32(limit))
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to search buyers: %v", err)})
	}

	if buyers == nil {
		buyers = []sqlc.Buyer{}
	}

	resp := make([]fiber.Map, len(buyers))
	for i, b := range buyers {
		resp[i] = flattenBuyer(b)
	}

	return c.Status(200).JSON(resp)
}

func (h *InvoiceHandler) PatchBuyer(c *fiber.Ctx) error {
	buyerID := c.Params("buyerId")
	if buyerID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: buyerId"})
	}

	body := map[string]json.RawMessage{}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body"})
	}

	allowed := map[string]struct{}{
		"buyerCode":    {},
		"buyerName":    {},
		"address":      {},
		"phoneNumber":  {},
		"idCardNumber": {},
		"email":        {},
		"taxId":        {},
		"lat":          {},
		"lng":          {},
	}

	for key := range body {
		if _, ok := allowed[key]; !ok {
			return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Unknown key: %s", key)})
		}
	}

	input := PatchBuyerInput{}
	if raw, ok := body["buyerCode"]; ok {
		var val string
		json.Unmarshal(raw, &val)
		if strings.HasPrefix(val, "KH-") {
			next := h.service.GetNextBuyerCodeInternal(context.Background())
			if val != next {
				return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Code mismatch! Next available code is %s", next)})
			}
		}
		input.BuyerCode = val
		input.SetBuyerCode = true
	}
	if raw, ok := body["buyerName"]; ok {
		var val string
		json.Unmarshal(raw, &val)
		input.BuyerName = val
		input.SetBuyerName = true
	}
	if raw, ok := body["address"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.Address = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetAddress = true
	}
	if raw, ok := body["phoneNumber"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.PhoneNumber = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetPhoneNumber = true
	}
	if raw, ok := body["idCardNumber"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.IDCardNumber = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetIDCardNumber = true
	}
	if raw, ok := body["email"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		if val != nil && *val != "" {
			if !isValidEmail(*val) {
				return c.Status(400).JSON(fiber.Map{"error": "Invalid email format"})
			}
		}
		input.Email = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetEmail = true
	}
	if raw, ok := body["taxId"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.TaxID = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetTaxID = true
	}
	if raw, ok := body["lat"]; ok {
		var val *float64
		json.Unmarshal(raw, &val)
		input.Lat = sql.NullFloat64{Float64: getFloat(val), Valid: val != nil}
		input.SetLat = true
	}
	if raw, ok := body["lng"]; ok {
		var val *float64
		json.Unmarshal(raw, &val)
		input.Lng = sql.NullFloat64{Float64: getFloat(val), Valid: val != nil}
		input.SetLng = true
	}

	buyID, _ := uuid.Parse(buyerID)
	buyer, err := h.service.PatchBuyer(context.Background(), buyID, input)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Buyer updated",
		"data":    flattenBuyer(buyer),
	})
}

func (h *InvoiceHandler) PatchInvoice(c *fiber.Ctx) error {
	invoiceID := c.Params("invoiceId")
	if invoiceID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	body := map[string]json.RawMessage{}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body"})
	}

	input := PatchInvoiceInput{}
	if raw, ok := body["buyerId"]; ok {
		var val string
		json.Unmarshal(raw, &val)
		bid, _ := uuid.Parse(val)
		input.BuyerID = uuid.NullUUID{UUID: bid, Valid: true}
		input.SetBuyerID = true
	}
	if raw, ok := body["invoiceCode"]; ok {
		var val string
		json.Unmarshal(raw, &val)
		loc, _ := time.LoadLocation("Asia/Ho_Chi_Minh")
		prefix := fmt.Sprintf("INV-%02d%02d%02d-", time.Now().In(loc).Year()%100, time.Now().In(loc).Month(), time.Now().In(loc).Day())
		if strings.HasPrefix(val, prefix) {
			next := h.service.GetNextInvoiceCodeInternal(context.Background())
			if val != next {
				return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Code mismatch! Next available code is %s", next)})
			}
		}
		input.InvoiceCode = val
		input.SetInvoiceCode = true
	}
	if raw, ok := body["buyerNameSnapshot"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.BuyerNameSnapshot = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetBuyerNameSnapshot = true
	}
	if raw, ok := body["addressSnapshot"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.AddressSnapshot = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetAddressSnapshot = true
	}
	if raw, ok := body["phoneNumberSnapshot"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.PhoneNumberSnapshot = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetPhoneNumberSnapshot = true
	}
	if raw, ok := body["idCardNumberSnapshot"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.IDCardNumberSnapshot = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetIDCardNumberSnapshot = true
	}
	if raw, ok := body["emailSnapshot"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		if val != nil && *val != "" {
			if !isValidEmail(*val) {
				return c.Status(400).JSON(fiber.Map{"error": "Invalid email format"})
			}
		}
		input.EmailSnapshot = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetEmailSnapshot = true
	}
	if raw, ok := body["latSnapshot"]; ok {
		var val *float64
		json.Unmarshal(raw, &val)
		input.LatSnapshot = sql.NullFloat64{Float64: getFloat(val), Valid: val != nil}
		input.SetLatSnapshot = true
	}
	if raw, ok := body["taxIdSnapshot"]; ok {
		var val *string
		json.Unmarshal(raw, &val)
		input.TaxIDSnapshot = sql.NullString{String: getString(val), Valid: val != nil}
		input.SetTaxIDSnapshot = true
	}
	if raw, ok := body["lngSnapshot"]; ok {
		var val *float64
		json.Unmarshal(raw, &val)
		input.LngSnapshot = sql.NullFloat64{Float64: getFloat(val), Valid: val != nil}
		input.SetLngSnapshot = true
	}

	invID, _ := uuid.Parse(invoiceID)
	invoice, err := h.service.PatchInvoice(context.Background(), invID, input)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Invoice updated",
		"data":    flattenInvoice(invoice),
	})
}

func (h *InvoiceHandler) PatchLineItem(c *fiber.Ctx) error {
	lineItemID := c.Params("lineItemId")
	if lineItemID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: lineItemId"})
	}

	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	body := map[string]json.RawMessage{}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body"})
	}

	liID, _ := uuid.Parse(lineItemID)
	lineItem, err := h.Repo.GetLineItemByID(context.Background(), liID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Line item not found"})
	}

	// Safety check: invoice must be in edit mode by this device
	invoice, err := h.service.GetInvoiceByID(context.Background(), lineItem.InvoiceID.UUID)
	if err == nil {
		if !invoice.EditStatus.Bool || (invoice.DeviceHoldingID.Valid && invoice.DeviceHoldingID.String != deviceHoldingID) {
			return c.Status(403).JSON(fiber.Map{"error": "Invoice is not in edit mode or deviceHoldingId mismatch"})
		}
	}

	input := PatchLineItemInput{}
	if raw, ok := body["quantity"]; ok {
		var val int32
		json.Unmarshal(raw, &val)
		input.Quantity = val
		input.SetQuantity = true
	}
	if raw, ok := body["unitPriceCustom"]; ok {
		var val *int64
		json.Unmarshal(raw, &val)
		input.UnitPriceCustom = sql.NullInt64{Int64: getInt64(val), Valid: val != nil}
		input.SetUnitPriceCustom = true
	}
	if raw, ok := body["itemNameSnapshot"]; ok {
		var val string
		json.Unmarshal(raw, &val)
		input.ItemNameSnapshot = sql.NullString{String: val, Valid: true}
		input.SetItemNameSnapshot = true
	}
	if raw, ok := body["unitNameSnapshot"]; ok {
		var val string
		json.Unmarshal(raw, &val)
		input.UnitNameSnapshot = sql.NullString{String: val, Valid: true}
		input.SetUnitNameSnapshot = true
	}

	updated, err := h.service.PatchLineItem(context.Background(), liID, input)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Line item updated", "data": flattenLineItem(updated)})
}

func (h *InvoiceHandler) DeleteLineItem(c *fiber.Ctx) error {
	lineItemIDStr := c.Params("lineItemId")
	liID, err := uuid.Parse(lineItemIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid lineItemId"})
	}

	err = h.service.DeleteLineItem(context.Background(), liID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to delete line item: %v", err)})
	}

	return c.SendStatus(204)
}

func (h *InvoiceHandler) GetInvoices(c *fiber.Ctx) error {
	showDraftStr := c.Query("showDraft")
	showSavedStr := c.Query("showSaved")
	showLockedStr := c.Query("showLocked")
	buyerIDStr := c.Query("buyerId")
	invoiceCode := c.Query("invoiceCode")
	itemIDStr := c.Query("itemId")
	limitStr := c.Query("limit", "20")
	offsetStr := c.Query("offset", "0")
	sortBy := c.Query("sortBy", "updated_at")
	sortOrder := c.Query("sortOrder", "desc")

	var showDraft, showSaved, showLocked bool
	if showDraftStr != "" || showSavedStr != "" || showLockedStr != "" {
		showDraft = showDraftStr == "true"
		showSaved = showSavedStr == "true"
		showLocked = showLockedStr == "true"
	} else {
		// Backward compatibility
		showEditingStr := c.Query("showEditing", "true")
		paidLockedStr := c.Query("paidLocked")

		showDraft = showEditingStr == "true"
		showLocked = paidLockedStr == "true"
		// If editing is enabled, saved (non-draft) are also enabled by default for back-compat
		showSaved = showEditingStr == "true"
	}

	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}

	offset, err := strconv.Atoi(offsetStr)
	if err != nil || offset < 0 {
		offset = 0
	}

	var buyerID *uuid.UUID
	if buyerIDStr != "" {
		parsed, err := uuid.Parse(buyerIDStr)
		if err == nil {
			buyerID = &parsed
		}
	}

	var itemID *uuid.UUID
	if itemIDStr != "" {
		parsed, err := uuid.Parse(itemIDStr)
		if err == nil {
			itemID = &parsed
		}
	}

	startDateStr := c.Query("startDate")
	endDateStr := c.Query("endDate")

	var startDate *time.Time
	if startDateStr != "" {
		if t, err := time.Parse(time.RFC3339, startDateStr); err == nil {
			startDate = &t
		} else if t, err := time.Parse("2006-01-02", startDateStr); err == nil {
			startDate = &t
		}
	}

	var endDate *time.Time
	if endDateStr != "" {
		if t, err := time.Parse(time.RFC3339, endDateStr); err == nil {
			endDate = &t
		} else if t, err := time.Parse("2006-01-02", endDateStr); err == nil {
			t = t.Add(23*time.Hour + 59*time.Minute + 59*time.Second)
			endDate = &t
		}
	}

	invoices, err := h.service.ListInvoicesFiltered(context.Background(), showDraft, showSaved, showLocked, buyerID, invoiceCode, itemID, startDate, endDate, int32(limit), int32(offset), sortBy, sortOrder)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to list invoices: %v", err)})
	}

	if invoices == nil {
		invoices = []sqlc.ListInvoicesFilteredRow{}
	}

	resp := []fiber.Map{}
	for _, inv := range invoices {
		resp = append(resp, flattenListInvoicesFilteredRow(inv))
	}

	return c.Status(200).JSON(fiber.Map{"data": resp})
}

func (h *InvoiceHandler) DeleteBuyer(c *fiber.Ctx) error {
	buyerID := c.Params("buyerId")
	if buyerID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: buyerId"})
	}

	err := h.service.DeleteBuyer(context.Background(), buyerID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to soft delete buyer: %v", err)})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Buyer soft deleted successfully"})
}

func (h *InvoiceHandler) RestoreBuyer(c *fiber.Ctx) error {
	buyerID := c.Params("buyerId")
	if buyerID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: buyerId"})
	}

	err := h.service.RestoreBuyer(context.Background(), buyerID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to restore buyer: %v", err)})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Buyer restored successfully"})
}

func (h *InvoiceHandler) GetDeletedBuyers(c *fiber.Ctx) error {
	buyers, err := h.service.GetDeletedBuyers(context.Background())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to get deleted buyers: %v", err)})
	}

	resp := []fiber.Map{}
	for _, buyer := range buyers {
		resp = append(resp, flattenBuyer(buyer))
	}

	return c.Status(200).JSON(resp)
}

func (h *InvoiceHandler) DeleteInvoice(c *fiber.Ctx) error {
	invoiceID := c.Params("invoiceId")
	if invoiceID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	err := h.service.DeleteInvoice(context.Background(), invoiceID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to soft delete invoice: %v", err)})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Invoice soft deleted successfully"})
}

func (h *InvoiceHandler) RestoreInvoice(c *fiber.Ctx) error {
	invoiceID := c.Params("invoiceId")
	if invoiceID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: invoiceId"})
	}

	err := h.service.RestoreInvoice(context.Background(), invoiceID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to restore invoice: %v", err)})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Invoice restored successfully"})
}

func (h *InvoiceHandler) GetDeletedInvoices(c *fiber.Ctx) error {
	invoices, err := h.service.GetDeletedInvoices(context.Background())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to get deleted invoices: %v", err)})
	}

	resp := []fiber.Map{}
	for _, inv := range invoices {
		resp = append(resp, flattenListDeletedInvoicesRow(inv))
	}

	return c.Status(200).JSON(fiber.Map{"data": resp})
}

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)

func isValidEmail(email string) bool {
	return emailRegex.MatchString(email)
}

func flattenInvoice(inv sqlc.Invoice) fiber.Map {
	var accountID *uuid.UUID
	if inv.AccountID.Valid {
		accountID = &inv.AccountID.UUID
	}
	var buyerID *uuid.UUID
	if inv.BuyerID.Valid {
		buyerID = &inv.BuyerID.UUID
	}
	var deviceHoldingID *string
	if inv.DeviceHoldingID.Valid {
		deviceHoldingID = &inv.DeviceHoldingID.String
	}
	var editStatus *bool
	if inv.EditStatus.Valid {
		editStatus = &inv.EditStatus.Bool
	}
	var paidLocked *bool
	if inv.PaidLocked.Valid {
		paidLocked = &inv.PaidLocked.Bool
	}
	var buyerNameSnapshot *string
	if inv.BuyerNameSnapshot.Valid {
		buyerNameSnapshot = &inv.BuyerNameSnapshot.String
	}
	var addressSnapshot *string
	if inv.AddressSnapshot.Valid {
		addressSnapshot = &inv.AddressSnapshot.String
	}
	var idCardNumberSnapshot *string
	if inv.IDCardNumberSnapshot.Valid {
		idCardNumberSnapshot = &inv.IDCardNumberSnapshot.String
	}
	var emailSnapshot *string
	if inv.EmailSnapshot.Valid {
		emailSnapshot = &inv.EmailSnapshot.String
	}
	var latSnapshot *float64
	if inv.LatSnapshot.Valid {
		latSnapshot = &inv.LatSnapshot.Float64
	}
	var lngSnapshot *float64
	if inv.LngSnapshot.Valid {
		lngSnapshot = &inv.LngSnapshot.Float64
	}
	var phoneNumberSnapshot *string
	if inv.PhoneNumberSnapshot.Valid {
		phoneNumberSnapshot = &inv.PhoneNumberSnapshot.String
	}
	var taxIDSnapshot *string
	if inv.TaxIDSnapshot.Valid {
		taxIDSnapshot = &inv.TaxIDSnapshot.String
	}
	var isActive *bool
	if inv.IsActive.Valid {
		isActive = &inv.IsActive.Bool
	}
	var createdAt *string
	if inv.CreatedAt.Valid {
		s := inv.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if inv.UpdatedAt.Valid {
		s := inv.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	var deletedAt *string
	if inv.DeletedAt.Valid {
		s := inv.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
	}

	return fiber.Map{
		"invoiceId":            inv.InvoiceID,
		"accountId":            accountID,
		"buyerId":              buyerID,
		"invoiceCode":          inv.InvoiceCode,
		"totalAmount":          inv.TotalAmount,
		"deviceHoldingId":      deviceHoldingID,
		"editStatus":           editStatus,
		"paidLocked":           paidLocked,
		"buyerNameSnapshot":    buyerNameSnapshot,
		"addressSnapshot":      addressSnapshot,
		"idCardNumberSnapshot": idCardNumberSnapshot,
		"emailSnapshot":        emailSnapshot,
		"latSnapshot":          latSnapshot,
		"lngSnapshot":          lngSnapshot,
		"phoneNumberSnapshot":  phoneNumberSnapshot,
		"taxIdSnapshot":        taxIDSnapshot,
		"isActive":             isActive,
		"createdAt":            createdAt,
		"updatedAt":            updatedAt,
		"deletedAt":            deletedAt,
	}
}

func flattenGetInvoiceByIDRow(inv sqlc.GetInvoiceByIDRow) fiber.Map {
	var accountID *uuid.UUID
	if inv.AccountID.Valid {
		accountID = &inv.AccountID.UUID
	}
	var buyerID *uuid.UUID
	if inv.BuyerID.Valid {
		buyerID = &inv.BuyerID.UUID
	}
	var deviceHoldingID *string
	if inv.DeviceHoldingID.Valid {
		deviceHoldingID = &inv.DeviceHoldingID.String
	}
	var editStatus *bool
	if inv.EditStatus.Valid {
		editStatus = &inv.EditStatus.Bool
	}
	var paidLocked *bool
	if inv.PaidLocked.Valid {
		paidLocked = &inv.PaidLocked.Bool
	}
	var buyerNameSnapshot *string
	if inv.BuyerNameSnapshot.Valid {
		buyerNameSnapshot = &inv.BuyerNameSnapshot.String
	}
	var addressSnapshot *string
	if inv.AddressSnapshot.Valid {
		addressSnapshot = &inv.AddressSnapshot.String
	}
	var idCardNumberSnapshot *string
	if inv.IDCardNumberSnapshot.Valid {
		idCardNumberSnapshot = &inv.IDCardNumberSnapshot.String
	}
	var emailSnapshot *string
	if inv.EmailSnapshot.Valid {
		emailSnapshot = &inv.EmailSnapshot.String
	}
	var latSnapshot *float64
	if inv.LatSnapshot.Valid {
		latSnapshot = &inv.LatSnapshot.Float64
	}
	var lngSnapshot *float64
	if inv.LngSnapshot.Valid {
		lngSnapshot = &inv.LngSnapshot.Float64
	}
	var phoneNumberSnapshot *string
	if inv.PhoneNumberSnapshot.Valid {
		phoneNumberSnapshot = &inv.PhoneNumberSnapshot.String
	}
	var taxIDSnapshot *string
	if inv.TaxIDSnapshot.Valid {
		taxIDSnapshot = &inv.TaxIDSnapshot.String
	}
	var isActive *bool
	if inv.IsActive.Valid {
		isActive = &inv.IsActive.Bool
	}
	var createdAt *string
	if inv.CreatedAt.Valid {
		s := inv.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if inv.UpdatedAt.Valid {
		s := inv.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	var deletedAt *string
	if inv.DeletedAt.Valid {
		s := inv.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
	}
	var buyerCode *string
	if inv.BuyerCode.Valid {
		buyerCode = &inv.BuyerCode.String
	}

	return fiber.Map{
		"invoiceId":            inv.InvoiceID,
		"accountId":            accountID,
		"buyerId":              buyerID,
		"invoiceCode":          inv.InvoiceCode,
		"totalAmount":          inv.TotalAmount,
		"deviceHoldingId":      deviceHoldingID,
		"editStatus":           editStatus,
		"paidLocked":           paidLocked,
		"buyerNameSnapshot":    buyerNameSnapshot,
		"addressSnapshot":      addressSnapshot,
		"idCardNumberSnapshot": idCardNumberSnapshot,
		"emailSnapshot":        emailSnapshot,
		"latSnapshot":          latSnapshot,
		"lngSnapshot":          lngSnapshot,
		"phoneNumberSnapshot":  phoneNumberSnapshot,
		"taxIdSnapshot":        taxIDSnapshot,
		"isActive":             isActive,
		"createdAt":            createdAt,
		"updatedAt":            updatedAt,
		"deletedAt":            deletedAt,
		"buyerCode":            buyerCode,
	}
}

func flattenListInvoicesFilteredRow(inv sqlc.ListInvoicesFilteredRow) fiber.Map {
	var accountID *uuid.UUID
	if inv.AccountID.Valid {
		accountID = &inv.AccountID.UUID
	}
	var buyerID *uuid.UUID
	if inv.BuyerID.Valid {
		buyerID = &inv.BuyerID.UUID
	}
	var deviceHoldingID *string
	if inv.DeviceHoldingID.Valid {
		deviceHoldingID = &inv.DeviceHoldingID.String
	}
	var editStatus *bool
	if inv.EditStatus.Valid {
		editStatus = &inv.EditStatus.Bool
	}
	var paidLocked *bool
	if inv.PaidLocked.Valid {
		paidLocked = &inv.PaidLocked.Bool
	}
	var buyerNameSnapshot *string
	if inv.BuyerNameSnapshot.Valid {
		buyerNameSnapshot = &inv.BuyerNameSnapshot.String
	}
	var addressSnapshot *string
	if inv.AddressSnapshot.Valid {
		addressSnapshot = &inv.AddressSnapshot.String
	}
	var idCardNumberSnapshot *string
	if inv.IDCardNumberSnapshot.Valid {
		idCardNumberSnapshot = &inv.IDCardNumberSnapshot.String
	}
	var emailSnapshot *string
	if inv.EmailSnapshot.Valid {
		emailSnapshot = &inv.EmailSnapshot.String
	}
	var latSnapshot *float64
	if inv.LatSnapshot.Valid {
		latSnapshot = &inv.LatSnapshot.Float64
	}
	var lngSnapshot *float64
	if inv.LngSnapshot.Valid {
		lngSnapshot = &inv.LngSnapshot.Float64
	}
	var phoneNumberSnapshot *string
	if inv.PhoneNumberSnapshot.Valid {
		phoneNumberSnapshot = &inv.PhoneNumberSnapshot.String
	}
	var taxIDSnapshot *string
	if inv.TaxIDSnapshot.Valid {
		taxIDSnapshot = &inv.TaxIDSnapshot.String
	}
	var isActive *bool
	if inv.IsActive.Valid {
		isActive = &inv.IsActive.Bool
	}
	var createdAt *string
	if inv.CreatedAt.Valid {
		s := inv.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if inv.UpdatedAt.Valid {
		s := inv.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	var deletedAt *string
	if inv.DeletedAt.Valid {
		s := inv.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
	}
	var deviceName *string
	if inv.DeviceName.Valid {
		deviceName = &inv.DeviceName.String
	}
	var buyerCode *string
	if inv.BuyerCode.Valid {
		buyerCode = &inv.BuyerCode.String
	}

	return fiber.Map{
		"invoiceId":            inv.InvoiceID,
		"accountId":            accountID,
		"buyerId":              buyerID,
		"invoiceCode":          inv.InvoiceCode,
		"totalAmount":          inv.TotalAmount,
		"deviceHoldingId":      deviceHoldingID,
		"deviceName":           deviceName,
		"editStatus":           editStatus,
		"paidLocked":           paidLocked,
		"buyerNameSnapshot":    buyerNameSnapshot,
		"addressSnapshot":      addressSnapshot,
		"idCardNumberSnapshot": idCardNumberSnapshot,
		"emailSnapshot":        emailSnapshot,
		"latSnapshot":          latSnapshot,
		"lngSnapshot":          lngSnapshot,
		"phoneNumberSnapshot":  phoneNumberSnapshot,
		"taxIdSnapshot":        taxIDSnapshot,
		"isActive":             isActive,
		"createdAt":            createdAt,
		"updatedAt":            updatedAt,
		"deletedAt":            deletedAt,
		"buyerCode":            buyerCode,
	}
}

func flattenListDeletedInvoicesRow(inv sqlc.ListDeletedInvoicesRow) fiber.Map {
	var accountID *uuid.UUID
	if inv.AccountID.Valid {
		accountID = &inv.AccountID.UUID
	}
	var buyerID *uuid.UUID
	if inv.BuyerID.Valid {
		buyerID = &inv.BuyerID.UUID
	}
	var deviceHoldingID *string
	if inv.DeviceHoldingID.Valid {
		deviceHoldingID = &inv.DeviceHoldingID.String
	}
	var editStatus *bool
	if inv.EditStatus.Valid {
		editStatus = &inv.EditStatus.Bool
	}
	var paidLocked *bool
	if inv.PaidLocked.Valid {
		paidLocked = &inv.PaidLocked.Bool
	}
	var buyerNameSnapshot *string
	if inv.BuyerNameSnapshot.Valid {
		buyerNameSnapshot = &inv.BuyerNameSnapshot.String
	}
	var addressSnapshot *string
	if inv.AddressSnapshot.Valid {
		addressSnapshot = &inv.AddressSnapshot.String
	}
	var idCardNumberSnapshot *string
	if inv.IDCardNumberSnapshot.Valid {
		idCardNumberSnapshot = &inv.IDCardNumberSnapshot.String
	}
	var emailSnapshot *string
	if inv.EmailSnapshot.Valid {
		emailSnapshot = &inv.EmailSnapshot.String
	}
	var latSnapshot *float64
	if inv.LatSnapshot.Valid {
		latSnapshot = &inv.LatSnapshot.Float64
	}
	var lngSnapshot *float64
	if inv.LngSnapshot.Valid {
		lngSnapshot = &inv.LngSnapshot.Float64
	}
	var phoneNumberSnapshot *string
	if inv.PhoneNumberSnapshot.Valid {
		phoneNumberSnapshot = &inv.PhoneNumberSnapshot.String
	}
	var taxIDSnapshot *string
	if inv.TaxIDSnapshot.Valid {
		taxIDSnapshot = &inv.TaxIDSnapshot.String
	}
	var isActive *bool
	if inv.IsActive.Valid {
		isActive = &inv.IsActive.Bool
	}
	var createdAt *string
	if inv.CreatedAt.Valid {
		s := inv.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if inv.UpdatedAt.Valid {
		s := inv.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	var deletedAt *string
	if inv.DeletedAt.Valid {
		s := inv.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
	}
	var deviceName *string
	if inv.DeviceName.Valid {
		deviceName = &inv.DeviceName.String
	}
	var buyerCode *string
	if inv.BuyerCode.Valid {
		buyerCode = &inv.BuyerCode.String
	}

	return fiber.Map{
		"invoiceId":            inv.InvoiceID,
		"accountId":            accountID,
		"buyerId":              buyerID,
		"invoiceCode":          inv.InvoiceCode,
		"totalAmount":          inv.TotalAmount,
		"deviceHoldingId":      deviceHoldingID,
		"deviceName":           deviceName,
		"editStatus":           editStatus,
		"paidLocked":           paidLocked,
		"buyerNameSnapshot":    buyerNameSnapshot,
		"addressSnapshot":      addressSnapshot,
		"idCardNumberSnapshot": idCardNumberSnapshot,
		"emailSnapshot":        emailSnapshot,
		"latSnapshot":          latSnapshot,
		"lngSnapshot":          lngSnapshot,
		"phoneNumberSnapshot":  phoneNumberSnapshot,
		"taxIdSnapshot":        taxIDSnapshot,
		"isActive":             isActive,
		"createdAt":            createdAt,
		"updatedAt":            updatedAt,
		"deletedAt":            deletedAt,
		"buyerCode":            buyerCode,
	}
}

func flattenBuyer(b sqlc.Buyer) fiber.Map {
	var addr, phone, idCard, email, taxID *string
	var lat, lng *float64
	var isActive *bool
	var createdAt, updatedAt, deletedAt *string

	if b.Address.Valid {
		addr = &b.Address.String
	}
	if b.PhoneNumber.Valid {
		phone = &b.PhoneNumber.String
	}
	if b.IDCardNumber.Valid {
		idCard = &b.IDCardNumber.String
	}
	if b.Email.Valid {
		email = &b.Email.String
	}
	if b.TaxID.Valid {
		taxID = &b.TaxID.String
	}
	if b.Lat.Valid {
		lat = &b.Lat.Float64
	}
	if b.Lng.Valid {
		lng = &b.Lng.Float64
	}
	if b.IsActive.Valid {
		isActive = &b.IsActive.Bool
	}
	if b.CreatedAt.Valid {
		s := b.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	if b.UpdatedAt.Valid {
		s := b.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	if b.DeletedAt.Valid {
		s := b.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
	}

	return fiber.Map{
		"buyerId":      b.BuyerID,
		"buyerCode":    b.BuyerCode,
		"buyerName":    b.BuyerName,
		"address":      addr,
		"phoneNumber":  phone,
		"idCardNumber": idCard,
		"email":        email,
		"taxId":        taxID,
		"lat":          lat,
		"lng":          lng,
		"isActive":     isActive,
		"createdAt":    createdAt,
		"updatedAt":    updatedAt,
		"deletedAt":    deletedAt,
	}
}

func flattenLineItem(li sqlc.LineItem) fiber.Map {
	var invoiceID *uuid.UUID
	if li.InvoiceID.Valid {
		invoiceID = &li.InvoiceID.UUID
	}
	var itemID *uuid.UUID
	if li.ItemID.Valid {
		itemID = &li.ItemID.UUID
	}
	var unitID *uuid.UUID
	if li.UnitID.Valid {
		unitID = &li.UnitID.UUID
	}
	var unitPriceCustom *int64
	if li.UnitPriceCustom.Valid {
		unitPriceCustom = &li.UnitPriceCustom.Int64
	}
	var itemNameSnapshot *string
	if li.ItemNameSnapshot.Valid {
		itemNameSnapshot = &li.ItemNameSnapshot.String
	}
	var unitNameSnapshot *string
	if li.UnitNameSnapshot.Valid {
		unitNameSnapshot = &li.UnitNameSnapshot.String
	}
	var createdAt *string
	if li.CreatedAt.Valid {
		s := li.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}

	return fiber.Map{
		"lineItemId":       li.LineItemID,
		"invoiceId":        invoiceID,
		"itemId":           itemID,
		"unitId":           unitID,
		"quantity":         li.Quantity,
		"unitPriceCustom":  unitPriceCustom,
		"subTotal":         li.SubTotal,
		"itemNameSnapshot": itemNameSnapshot,
		"unitNameSnapshot": unitNameSnapshot,
		"positionKey":      li.PositionKey,
		"createdAt":        createdAt,
	}
}

func flattenDevice(d sqlc.Device) fiber.Map {
	var deviceName *string
	if d.DeviceName.Valid {
		deviceName = &d.DeviceName.String
	}
	return fiber.Map{
		"deviceHoldingId": d.DeviceHoldingID,
		"deviceName":      deviceName,
	}
}
