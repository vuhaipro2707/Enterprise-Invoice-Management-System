package item

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"strings"

	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
)

type ItemHandler struct {
	Repo    *sqlc.Queries
	service *ItemService
}

func NewItemHandler(repo *sqlc.Queries) *ItemHandler {
	return &ItemHandler{
		Repo:    repo,
		service: NewItemService(repo),
	}
}

// example request body for CreateItem:
//
//	{
//	    "itemFormalName": "Example Item",
//	    "itemShortNames": ["ExItem", "Example"],
//	    "typeId": "optional-type-uuid",
//	    "unitId": "optional-unit-uuid"
//	}
func (h *ItemHandler) CreateItem(c *fiber.Ctx) error {
	type createItemRequest struct {
		ItemFormalName string   `json:"itemFormalName"`
		ItemShortNames []string `json:"itemShortNames"`
		TypeID         string   `json:"typeId"`
	}

	var req createItemRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required keys: itemFormalName, itemShortNames, typeId(optional)"})
	}

	if req.ItemFormalName == "" || len(req.ItemShortNames) == 0 {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: itemFormalName, itemShortNames, typeId(optional)"})
	}

	item, err := h.service.CreateItem(context.Background(), req.ItemFormalName, req.ItemShortNames, req.TypeID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Failed to create item. Please verify typeId/unitId are valid UUIDs and related records exist"})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Item created successfully",
		"data":    item,
	})
}

// example response body for GetItems:
//
//	{
//	    "data": [
//	        {
//	            "item_id": "item-uuid",
//	            "item_formal_name": "Example Item",
//	            "item_short_names": ["ExItem", "Example"],
//	            "type_id": "optional-type-uuid",
//	            "unit_id": "optional-unit-uuid"
//	        },
//	        ...
//	    ]
//	}
func (h *ItemHandler) GetItems(c *fiber.Ctx) error {
	items, err := h.service.GetItems(context.Background())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to get items"})
	}

	return c.Status(200).JSON(fiber.Map{"data": items})
}

// example query: GET /items/search?keyword=example&limit=10
// example response body for SearchItems:
//
//	{
//	    "data": [
//	        {
//	            "item_id": "item-uuid",
//	            "item_formal_name": "Example Item",
//	            "item_short_names": ["ExItem", "Example"],
//	            "type_id": "optional-type-uuid",
//	            "unit_id": "optional-unit-uuid"
//	        },
//	        ...
//	    ]
//	}
func (h *ItemHandler) SearchItems(c *fiber.Ctx) error {
	keyword := c.Query("keyword")
	if keyword == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing query parameter: keyword"})
	}

	replacer := strings.NewReplacer("[", "", "]", "", "\"", "", ",", "")
	sanitizedKeyword := replacer.Replace(keyword) // JsonB of short names be treated as text, so remove special chars to improve search relevance

	limitStr := c.Query("limit", "10")
	parsedLimit, err := strconv.ParseInt(limitStr, 10, 32)
	limit := int32(parsedLimit)
	if err != nil || limit <= 0 {
		limit = 10
	}
	if limit > 100 {
		limit = 100
	}

	items, err := h.service.SearchItems(context.Background(), sanitizedKeyword, limit)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to search items"})
	}

	if items == nil {
		items = []sqlc.Item{}
	}

	return c.Status(200).JSON(fiber.Map{"data": items})
}

// example request body for CreateUnitForItem:
//
//	{
//	    "unitName": "Example Unit",
//	    "unitPriceDefault": 100
//	}
func (h *ItemHandler) CreateUnitForItem(c *fiber.Ctx) error {
	type createUnitRequest struct {
		UnitName         string `json:"unitName"`
		UnitPriceDefault *int64 `json:"unitPriceDefault"`
	}

	itemID := c.Params("itemId")
	if itemID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: itemId"})
	}

	var req createUnitRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required keys: unitName, unitPriceDefault(optional)"})
	}

	if req.UnitName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: unitName, unitPriceDefault(optional)"})
	}

	unit, err := h.service.CreateUnitForItem(context.Background(), itemID, req.UnitName, req.UnitPriceDefault)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.Status(404).JSON(fiber.Map{"error": "Item not found"})
		}
		return c.Status(400).JSON(fiber.Map{"error": "Failed to create unit for item. Please verify itemId is a valid UUID and item exists"})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Unit created and assigned to item successfully",
		"data":    unit,
	})
}

// example response body for GetUnits:
//
//	{
//	    "data": [
//	        {
//	            "unit_id": "unit-uuid",
//	            "unit_name": "Example Unit",
//	            "unit_price_default": 100
//	        },
//	        ...
//	    ]
//	}
func (h *ItemHandler) GetUnits(c *fiber.Ctx) error {
	units, err := h.service.GetUnits(context.Background())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to get units"})
	}

	return c.Status(200).JSON(fiber.Map{"data": units})
}

// example request body for CreateType:
//
//	{
//	    "typeName": "Example Type"
//	}
func (h *ItemHandler) CreateType(c *fiber.Ctx) error {
	type createTypeRequest struct {
		TypeName string `json:"typeName"`
	}

	var req createTypeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required keys: typeName"})
	}

	if req.TypeName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: typeName"})
	}

	typeData, err := h.service.CreateType(context.Background(), req.TypeName)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Failed to create type. typeName might already exist"})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Type created successfully",
		"data":    typeData,
	})
}

// example response body for GetTypes:
//
//	{
//	    "data": [
//	        {
//	            "type_id": "type-uuid",
//	            "type_name": "Example Type"
//	        },
//	        ...
//	    ]
//	}
func (h *ItemHandler) GetTypes(c *fiber.Ctx) error {
	types, err := h.service.GetTypes(context.Background())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to get types"})
	}

	return c.Status(200).JSON(fiber.Map{"data": types})
}
