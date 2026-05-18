package invoice

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	sqlc "invoice_backend/db/sqlc"
	"net/url"
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
		Lat          *float64 `json:"lat"`
		Lng          *float64 `json:"lng"`
	}

	var req createBuyerRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required keys: buyerCode, buyerName. Optional: address, phoneNumber, idCardNumber, lat, lng"})
	}

	if req.BuyerCode == "" || req.BuyerName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: buyerCode, buyerName, address(optional), phoneNumber(optional), idCardNumber(optional), lat(optional), lng(optional)"})
	}

	buyer, err := h.service.CreateBuyer(context.Background(), req.BuyerCode, req.BuyerName, req.Address, req.PhoneNumber, req.IdCardNumber, req.Lat, req.Lng)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Buyer created successfully",
		"data":    buyer,
	})
}

func (h *InvoiceHandler) CreateInvoice(c *fiber.Ctx) error {
	type createInvoiceRequest struct {
		BuyerID       *string `json:"buyerId"`
		InvoiceCode   string  `json:"invoiceCode"`
		EditStatus    bool    `json:"editStatus"`
		BuyerNameSnap *string `json:"buyerNameSnapshot"`
		AddressSnap   *string `json:"addressSnapshot"`
		PhoneSnap     *string `json:"phoneNumberSnapshot"`
	}

	deviceHoldingID := c.Get("X-Device-Holding-ID")
	if deviceHoldingID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing header: X-Device-Holding-ID"})
	}

	var req createInvoiceRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required: invoiceCode. Optional: buyerId, editStatus, buyerNameSnapshot, addressSnapshot, phoneNumberSnapshot"})
	}

	if req.InvoiceCode == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: invoiceCode, buyerId(optional), editStatus(optional), buyerNameSnapshot(optional if buyerId provided), addressSnapshot(optional), phoneNumberSnapshot(optional)"})
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
	if req.BuyerID != nil && (req.BuyerNameSnap == nil || req.AddressSnap == nil || req.PhoneSnap == nil) {
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
		}
	}

	// TotalAmount is handled by trigger based on line items, initial is 0
	invoice, err := h.service.CreateInvoice(context.Background(), account.AccountID, buyID, req.InvoiceCode, 0, deviceHoldingID, req.EditStatus, req.BuyerNameSnap, req.AddressSnap, req.PhoneSnap)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to create invoice: %v", err)})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Invoice created successfully",
		"data":    invoice,
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

	// Calculate position_key (insert at end)
	invoiceWithLines, _ := h.service.Repo.GetInvoiceWithLines(context.Background(), invID)
	posKey := "i0000" // Default for the first item
	var lines []map[string]interface{}
	if invoiceWithLines.LineItems != nil {
		json.Unmarshal(invoiceWithLines.LineItems, &lines)
	}
	if len(lines) > 0 {
		lastLine := lines[len(lines)-1]
		if lastPos, ok := lastLine["position_key"].(string); ok {
			posKey = GenerateMidString(lastPos, "zzzzz")
		}
	}

	// sub_total is calculated by DB trigger, we pass 0 from app
	lineItem, err := h.service.CreateLineItem(context.Background(), invID, itmID, untID, req.Quantity, req.UnitPriceCustom, 0, getString(req.ItemNameSnapshot), getString(req.UnitNameSnapshot), posKey)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Failed to create line item: %v", err)})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Line item created successfully",
		"data":    lineItem,
	})
}

func (h *InvoiceHandler) ChangeLineItemOrder(c *fiber.Ctx) error {
	type changeOrderRequest struct {
		PrevLineItemID *string `json:"prev_line_item_id"`
		NextLineItemID *string `json:"next_line_item_id"`
		LineItemID     string  `json:"line_item_id"`
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
		return c.Status(400).JSON(fiber.Map{"error": "Invalid line_item_id"})
	}

	invoiceWithLines, err := h.service.Repo.GetInvoiceWithLines(context.Background(), invID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Invoice not found"})
	}

	var lines []map[string]interface{}
	json.Unmarshal(invoiceWithLines.LineItems, &lines)

	var prevKey, nextKey string
	for _, l := range lines {
		id := l["line_item_id"].(string)
		pk := l["position_key"].(string)
		if req.PrevLineItemID != nil && *req.PrevLineItemID == id {
			prevKey = pk
		}
		if req.NextLineItemID != nil && *req.NextLineItemID == id {
			nextKey = pk
		}
	}

	newPosKey := GenerateMidString(prevKey, nextKey)

	err = h.service.Repo.UpdateLineItemPos(context.Background(), sqlc.UpdateLineItemPosParams{
		LineItemID:  targetUUID,
		PositionKey: newPosKey,
	})
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Order updated", "new_position_key": newPosKey})
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

	return c.Status(200).JSON(fiber.Map{
		"message": "Took turn successfully",
		"data":    invoice,
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

	return c.Status(200).JSON(fiber.Map{
		"message": "Finished successfully",
		"data":    updatedInvoice,
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

	return c.Status(200).JSON(fiber.Map{
		"device_holding_id": invoice.DeviceHoldingID.String,
		"device_name":       invoice.DeviceName.String,
		"edit_status":       invoice.EditStatus.Bool,
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

	var addr, phone, idCard *string
	var lat, lng *float64
	if buyer.Address.Valid {
		addr = &buyer.Address.String
	}
	if buyer.PhoneNumber.Valid {
		phone = &buyer.PhoneNumber.String
	}
	if buyer.IDCardNumber.Valid {
		idCard = &buyer.IDCardNumber.String
	}
	if buyer.Lat.Valid {
		lat = &buyer.Lat.Float64
	}
	if buyer.Lng.Valid {
		lng = &buyer.Lng.Float64
	}

	return c.Status(200).JSON(fiber.Map{
		"buyer_id":       buyer.BuyerID,
		"buyer_code":     buyer.BuyerCode,
		"buyer_name":     buyer.BuyerName,
		"address":        addr,
		"phone_number":   phone,
		"id_card_number": idCard,
		"lat":            lat,
		"lng":            lng,
	})
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
		"data":    device,
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
		"data":       device,
	})
}

func (h *InvoiceHandler) GetNextBuyerCode(c *fiber.Ctx) error {
	lastCode, err := h.service.GetLastBuyerCode(context.Background())
	if err != nil {
		return c.Status(200).JSON(fiber.Map{"nextCode": "KH-001"})
	}

	// lastCode format example: "KH-005"
	var num int
	_, err = fmt.Sscanf(lastCode, "KH-%d", &num)
	if err != nil {
		return c.Status(200).JSON(fiber.Map{"nextCode": "KH-001"})
	}

	nextCode := fmt.Sprintf("KH-%03d", num+1)
	return c.Status(200).JSON(fiber.Map{"nextCode": nextCode})
}

func (h *InvoiceHandler) GetNextInvoiceCode(c *fiber.Ctx) error {
	loc, _ := time.LoadLocation("Asia/Ho_Chi_Minh")
	now := time.Now().In(loc)
	prefix := fmt.Sprintf("INV-%02d%02d%02d-", now.Year()%100, now.Month(), now.Day())
	pattern := prefix + "%"

	lastCode, err := h.service.GetLastInvoiceCode(context.Background(), pattern)
	if err != nil {
		return c.Status(200).JSON(fiber.Map{"nextCode": prefix + "001"})
	}

	var num int
	_, err = fmt.Sscanf(lastCode, prefix+"%d", &num)
	if err != nil {
		return c.Status(200).JSON(fiber.Map{"nextCode": prefix + "001"})
	}

	nextCode := fmt.Sprintf("%s%03d", prefix, num+1)
	return c.Status(200).JSON(fiber.Map{"nextCode": nextCode})
}

func (h *InvoiceHandler) ListEditingInvoices(c *fiber.Ctx) error {
	invoices, err := h.service.ListEditingInvoices(context.Background())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to list editing invoices: %v", err)})
	}

	if invoices == nil {
		invoices = []sqlc.ListEditingInvoicesRow{}
	}

	return c.Status(200).JSON(invoices)
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

	return c.Status(200).JSON(invoice)
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

	// Priority: Custom location (10.7449508, 106.6506517) with radius (around 30km)
	googleUrl := fmt.Sprintf("https://maps.googleapis.com/maps/api/place/autocomplete/json?input=%s&key=%s&language=vi&components=country:vn&location=10.7449508,106.6506517&radius=30000", url.QueryEscape(keyword), apiKey)
	if sessionToken != "" {
		googleUrl += "&sessiontoken=" + url.QueryEscape(sessionToken)
	}

	agent := fiber.Get(googleUrl)
	statusCode, body, errs := agent.Bytes()
	if len(errs) > 0 {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to call Google API: %v", errs[0])})
	}

	if statusCode != 200 {
		return c.Status(statusCode).Send(body)
	}

	var result map[string]interface{}
	json.Unmarshal(body, &result)

	// Enrich addresses in predictions
	if predictions, ok := result["predictions"].([]interface{}); ok {
		for _, p := range predictions {
			if predMap, ok := p.(map[string]interface{}); ok {
				// Enrich main description
				if desc, ok := predMap["description"].(string); ok {
					predMap["description"] = EnrichAddress(desc)
				}
				// Enrich structured_formatting.secondary_text
				if structForm, ok := predMap["structured_formatting"].(map[string]interface{}); ok {
					if secText, ok := structForm["secondary_text"].(string); ok {
						structForm["secondary_text"] = EnrichAddress(secText)
					}
				}
			}
		}
	}

	return c.JSON(result)
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

	googleUrl := fmt.Sprintf("https://maps.googleapis.com/maps/api/place/details/json?place_id=%s&fields=geometry&key=%s", url.QueryEscape(placeID), apiKey)
	if sessionToken != "" {
		googleUrl += "&sessiontoken=" + url.QueryEscape(sessionToken)
	}

	agent := fiber.Get(googleUrl)
	statusCode, body, errs := agent.Bytes()
	if len(errs) > 0 {
		return c.Status(500).JSON(fiber.Map{"error": fmt.Sprintf("Failed to call Google API: %v", errs[0])})
	}

	if statusCode != 200 {
		return c.Status(statusCode).Send(body)
	}

	var result map[string]interface{}
	json.Unmarshal(body, &result)
	// Enrich address in details result
	if result["status"] == "OK" {
		if resultData, ok := result["result"].(map[string]interface{}); ok {
			if formattedAddr, ok := resultData["formatted_address"].(string); ok {
				resultData["formatted_address"] = EnrichAddress(formattedAddr)
			}
		}
	}
	return c.JSON(result)
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
		var addr, phone, idCard *string
		var lat, lng *float64
		if b.Address.Valid {
			addr = &b.Address.String
		}
		if b.PhoneNumber.Valid {
			phone = &b.PhoneNumber.String
		}
		if b.IDCardNumber.Valid {
			idCard = &b.IDCardNumber.String
		}
		if b.Lat.Valid {
			lat = &b.Lat.Float64
		}
		if b.Lng.Valid {
			lng = &b.Lng.Float64
		}
		resp[i] = fiber.Map{
			"buyer_id":       b.BuyerID,
			"buyer_code":     b.BuyerCode,
			"buyer_name":     b.BuyerName,
			"address":        addr,
			"phone_number":   phone,
			"id_card_number": idCard,
			"lat":            lat,
			"lng":            lng,
		}
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
		var addr, phone, idCard *string
		var lat, lng *float64
		if b.Address.Valid {
			addr = &b.Address.String
		}
		if b.PhoneNumber.Valid {
			phone = &b.PhoneNumber.String
		}
		if b.IDCardNumber.Valid {
			idCard = &b.IDCardNumber.String
		}
		if b.Lat.Valid {
			lat = &b.Lat.Float64
		}
		if b.Lng.Valid {
			lng = &b.Lng.Float64
		}
		resp[i] = fiber.Map{
			"buyer_id":       b.BuyerID,
			"buyer_code":     b.BuyerCode,
			"buyer_name":     b.BuyerName,
			"address":        addr,
			"phone_number":   phone,
			"id_card_number": idCard,
			"lat":            lat,
			"lng":            lng,
		}
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

	return c.Status(200).JSON(fiber.Map{"message": "Buyer updated", "data": buyer})
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

	invID, _ := uuid.Parse(invoiceID)
	invoice, err := h.service.PatchInvoice(context.Background(), invID, input)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Invoice updated", "data": invoice})
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

	return c.Status(200).JSON(fiber.Map{"message": "Line item updated", "data": updated})
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
