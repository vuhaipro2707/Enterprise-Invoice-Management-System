package pricelist

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"invoice_backend/app/invoice"
	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
)

type PriceListHandler struct {
	Repo    *sqlc.Queries
	service *PriceListService
}

func NewPriceListHandler(repo *sqlc.Queries) *PriceListHandler {
	return &PriceListHandler{
		Repo:    repo,
		service: NewPriceListService(repo),
	}
}

func (h *PriceListHandler) CreatePriceList(c *fiber.Ctx) error {
	var req CreatePriceListInput
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid JSON body. Required keys: description, buyerId(optional), items",
		})
	}

	var missing []string
	if req.Description == "" {
		missing = append(missing, "description")
	}
	if req.Items == nil {
		missing = append(missing, "items")
	}

	if len(missing) > 0 {
		return c.Status(400).JSON(fiber.Map{
			"error": fmt.Sprintf("Missing required keys: %s, buyerId(optional)", strings.Join(missing, ", ")),
		})
	}

	for idx, itm := range req.Items {
		if itm.ItemID == "" {
			return c.Status(400).JSON(fiber.Map{
				"error": fmt.Sprintf("Missing required key in items[%d]: itemId, unitId(optional)", idx),
			})
		}
	}

	cpl, err := h.service.CreatePriceList(c.UserContext(), req)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to create customer price list: %s", err.Error()),
		})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Customer price list created successfully",
		"data":    flattenCustomerPriceList(cpl),
	})
}

func (h *PriceListHandler) GetPriceListByID(c *fiber.Ctx) error {
	id := c.Params("pricelistId")
	if id == "" {
		return c.Status(400).JSON(fiber.Map{
			"error": "Missing path parameter: pricelistId",
		})
	}

	row, err := h.service.GetPriceListByID(c.UserContext(), id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.Status(404).JSON(fiber.Map{
				"error": fmt.Sprintf("Customer price list not found with ID: %s", id),
			})
		}
		return c.Status(400).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to retrieve customer price list: %s", err.Error()),
		})
	}

	return c.Status(200).JSON(flattenGetPriceListByIDRow(row))
}

func (h *PriceListHandler) GetPriceLists(c *fiber.Ctx) error {
	buyerIDStr := c.Query("buyerId")
	keyword := c.Query("buyerName")
	limitStr := c.Query("limit", "20")
	offsetStr := c.Query("offset", "0")
	sortBy := c.Query("sortBy", "updated_at")
	sortOrder := c.Query("sortOrder", "desc")
	startDateStr := c.Query("startDate")
	endDateStr := c.Query("endDate")

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

	lists, err := h.service.ListPriceLists(c.UserContext(), buyerIDStr, keyword, int32(limit), int32(offset), sortBy, sortOrder, startDate, endDate)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to list customer price lists: %s", err.Error()),
		})
	}

	resp := []fiber.Map{}
	for _, l := range lists {
		resp = append(resp, flattenListPriceListRow(l))
	}

	return c.Status(200).JSON(fiber.Map{
		"data": resp,
	})
}

func (h *PriceListHandler) UpdatePriceList(c *fiber.Ctx) error {
	id := c.Params("pricelistId")
	if id == "" {
		return c.Status(400).JSON(fiber.Map{
			"error": "Missing path parameter: pricelistId",
		})
	}

	var req CreatePriceListInput
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid JSON body. Required keys: description, buyerId(optional), items",
		})
	}

	var missing []string
	if req.Description == "" {
		missing = append(missing, "description")
	}
	if req.Items == nil {
		missing = append(missing, "items")
	}

	if len(missing) > 0 {
		return c.Status(400).JSON(fiber.Map{
			"error": fmt.Sprintf("Missing required keys: %s, buyerId(optional)", strings.Join(missing, ", ")),
		})
	}

	for idx, itm := range req.Items {
		if itm.ItemID == "" {
			return c.Status(400).JSON(fiber.Map{
				"error": fmt.Sprintf("Missing required key in items[%d]: itemId, unitId(optional)", idx),
			})
		}
	}

	cpl, err := h.service.UpdatePriceList(c.UserContext(), id, req)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to update customer price list: %s", err.Error()),
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Customer price list updated successfully",
		"data":    flattenCustomerPriceList(cpl),
	})
}

func (h *PriceListHandler) DeletePriceList(c *fiber.Ctx) error {
	id := c.Params("pricelistId")
	if id == "" {
		return c.Status(400).JSON(fiber.Map{
			"error": "Missing path parameter: pricelistId",
		})
	}

	err := h.service.DeletePriceList(c.UserContext(), id)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to delete customer price list: %s", err.Error()),
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Customer price list deleted successfully",
	})
}

func flattenCustomerPriceList(cpl sqlc.CustomerPriceList) fiber.Map {
	var buyerID *uuid.UUID
	if cpl.BuyerID.Valid {
		buyerID = &cpl.BuyerID.UUID
	}
	var isActive *bool
	if cpl.IsActive.Valid {
		isActive = &cpl.IsActive.Bool
	}
	var createdAt *string
	if cpl.CreatedAt.Valid {
		s := cpl.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if cpl.UpdatedAt.Valid {
		s := cpl.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	var deletedAt *string
	if cpl.DeletedAt.Valid {
		s := cpl.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
	}

	return fiber.Map{
		"customer_price_list_id": cpl.CustomerPriceListID,
		"description":            cpl.Description,
		"buyer_id":               buyerID,
		"is_active":              isActive,
		"created_at":             createdAt,
		"updated_at":             updatedAt,
		"deleted_at":             deletedAt,
	}
}

func flattenListPriceListRow(row sqlc.ListCustomerPriceListsFilteredRow) fiber.Map {
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
		s := row.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if row.UpdatedAt.Valid {
		s := row.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	var deletedAt *string
	if row.DeletedAt.Valid {
		s := row.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
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

	return fiber.Map{
		"customer_price_list_id": row.CustomerPriceListID,
		"description":            row.Description,
		"buyer_id":               buyerID,
		"is_active":              isActive,
		"created_at":             createdAt,
		"updated_at":             updatedAt,
		"deleted_at":             deletedAt,
		"buyer_code":             buyerCode,
		"buyer_name":             buyerName,
		"phone_number":           phoneNumber,
		"address":                address,
	}
}

func flattenGetPriceListByIDRow(row sqlc.GetCustomerPriceListByIDRow) fiber.Map {
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
		s := row.CreatedAt.Time.Format(time.RFC3339)
		createdAt = &s
	}
	var updatedAt *string
	if row.UpdatedAt.Valid {
		s := row.UpdatedAt.Time.Format(time.RFC3339)
		updatedAt = &s
	}
	var deletedAt *string
	if row.DeletedAt.Valid {
		s := row.DeletedAt.Time.Format(time.RFC3339)
		deletedAt = &s
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

	return fiber.Map{
		"customer_price_list_id": row.CustomerPriceListID,
		"description":            row.Description,
		"buyer_id":               buyerID,
		"is_active":              isActive,
		"created_at":             createdAt,
		"updated_at":             updatedAt,
		"deleted_at":             deletedAt,
		"buyer_code":             buyerCode,
		"buyer_name":             buyerName,
		"phone_number":           phoneNumber,
		"address":                address,
		"item_prices":            itemPrices,
	}
}

func (h *PriceListHandler) ChangePriceItemOrder(c *fiber.Ctx) error {
	type changeOrderRequest struct {
		PrevCustomerItemPriceID *string `json:"prev_customer_item_price_id"`
		NextCustomerItemPriceID *string `json:"next_customer_item_price_id"`
		CustomerItemPriceID     string  `json:"customer_item_price_id"`
	}

	var req changeOrderRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid body"})
	}

	pricelistIDStr := c.Params("pricelistId")
	plID, err := uuid.Parse(pricelistIDStr)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid pricelistId"})
	}

	targetUUID, err := uuid.Parse(req.CustomerItemPriceID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid customer_item_price_id"})
	}

	row, err := h.service.Repo.GetCustomerPriceListByID(c.UserContext(), plID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "Pricelist not found"})
	}

	var itemPrices []map[string]interface{}
	if row.ItemPrices != nil {
		json.Unmarshal(row.ItemPrices, &itemPrices)
	}

	var prevKey, nextKey string
	for _, item := range itemPrices {
		id, _ := item["customer_item_price_id"].(string)
		pk, _ := item["position_key"].(string)
		if req.PrevCustomerItemPriceID != nil && *req.PrevCustomerItemPriceID == id {
			prevKey = pk
		}
		if req.NextCustomerItemPriceID != nil && *req.NextCustomerItemPriceID == id {
			nextKey = pk
		}
	}

	newPosKey := invoice.GenerateMidString(prevKey, nextKey)

	err = h.service.Repo.UpdateCustomerItemPricePos(c.UserContext(), sqlc.UpdateCustomerItemPricePosParams{
		CustomerItemPriceID: targetUUID,
		PositionKey:         newPosKey,
	})
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Order updated", "new_position_key": newPosKey})
}

func (h *PriceListHandler) RestorePriceList(c *fiber.Ctx) error {
	id := c.Params("pricelistId")
	if id == "" {
		return c.Status(400).JSON(fiber.Map{
			"error": "Missing path parameter: pricelistId",
		})
	}

	err := h.service.RestorePriceList(c.UserContext(), id)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to restore customer price list: %s", err.Error()),
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Customer price list restored successfully",
	})
}

func (h *PriceListHandler) GetDeletedPriceLists(c *fiber.Ctx) error {
	lists, err := h.service.GetDeletedPriceLists(c.UserContext())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to list deleted customer price lists: %s", err.Error()),
		})
	}

	resp := []fiber.Map{}
	for _, l := range lists {
		var buyerID *uuid.UUID
		if l.BuyerID.Valid {
			buyerID = &l.BuyerID.UUID
		}
		var isActive *bool
		if l.IsActive.Valid {
			isActive = &l.IsActive.Bool
		}
		var createdAt *string
		if l.CreatedAt.Valid {
			s := l.CreatedAt.Time.Format(time.RFC3339)
			createdAt = &s
		}
		var updatedAt *string
		if l.UpdatedAt.Valid {
			s := l.UpdatedAt.Time.Format(time.RFC3339)
			updatedAt = &s
		}
		var deletedAt *string
		if l.DeletedAt.Valid {
			s := l.DeletedAt.Time.Format(time.RFC3339)
			deletedAt = &s
		}
		var buyerCode *string
		if l.BuyerCode.Valid {
			buyerCode = &l.BuyerCode.String
		}
		var buyerName *string
		if l.BuyerName.Valid {
			buyerName = &l.BuyerName.String
		}
		var phoneNumber *string
		if l.PhoneNumber.Valid {
			phoneNumber = &l.PhoneNumber.String
		}
		var address *string
		if l.Address.Valid {
			address = &l.Address.String
		}

		resp = append(resp, fiber.Map{
			"customer_price_list_id": l.CustomerPriceListID,
			"description":            l.Description,
			"buyer_id":               buyerID,
			"is_active":              isActive,
			"created_at":             createdAt,
			"updated_at":             updatedAt,
			"deleted_at":             deletedAt,
			"buyer_code":             buyerCode,
			"buyer_name":             buyerName,
			"phone_number":           phoneNumber,
			"address":                address,
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"data": resp,
	})
}
