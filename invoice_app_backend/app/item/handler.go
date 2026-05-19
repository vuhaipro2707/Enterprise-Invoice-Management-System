package item

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"

	sqlc "invoice_backend/db/sqlc"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
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

var patchForbiddenKeys = map[string]struct{}{
	"isActive":  {},
	"createdAt": {},
	"updatedAt": {},
	"deletedAt": {},
}

func splitPatchKeys(body map[string]json.RawMessage, allowed map[string]struct{}) ([]string, []string) {
	forbidden := []string{}
	unknown := []string{}

	for key := range body {
		if _, blocked := patchForbiddenKeys[key]; blocked {
			forbidden = append(forbidden, key)
			continue
		}

		if _, ok := allowed[key]; !ok {
			unknown = append(unknown, key)
		}
	}

	return forbidden, unknown
}

// example request body for CreateItem:
//
//	{
//	    "itemDefaultName": "Example Item",
//	    "itemOtherNames": ["ExItem", "Example"],
//	    "typeId": "optional-type-uuid",
//	    "unitId": "optional-unit-uuid"
//	}
func (h *ItemHandler) CreateItem(c *fiber.Ctx) error {
	type createItemRequest struct {
		ItemDefaultName string   `json:"itemDefaultName"`
		ItemOtherNames  []string `json:"itemOtherNames"`
		TypeID          string   `json:"typeId"`
	}

	var req createItemRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required keys: itemDefaultName, itemOtherNames, typeId(optional)"})
	}

	if req.ItemDefaultName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required keys: itemDefaultName, typeId(optional)"})
	}

	item, err := h.service.CreateItem(context.Background(), req.ItemDefaultName, req.ItemOtherNames, req.TypeID)
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
//	            "item_default_name": "Example Item",
//	            "item_other_names": ["ExItem", "Example"],
//	            "type_id": "optional-type-uuid",
//	            "unit_id": "optional-unit-uuid"
//	        },
//	        ...
//	    ]
//	}
func (h *ItemHandler) GetItems(c *fiber.Ctx) error {
	typeIDStr := c.Query("typeId")
	limitStr := c.Query("limit", "20")
	offsetStr := c.Query("offset", "0")
	sortBy := c.Query("sortBy", "")
	sortOrder := c.Query("sortOrder", "asc")

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

	var typeID *uuid.UUID
	if typeIDStr != "" {
		parsedTypeID, err := uuid.Parse(typeIDStr)
		if err == nil {
			typeID = &parsedTypeID
		}
	}

	items, err := h.service.GetItemsFiltered(context.Background(), typeID, int32(limit), int32(offset), sortBy, sortOrder)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to get items"})
	}

	resp := []fiber.Map{}
	for _, item := range items {
		var tID *uuid.UUID
		if item.TypeID.Valid {
			tID = &item.TypeID.UUID
		}

		var units []interface{}
		if item.Units != nil {
			json.Unmarshal(item.Units, &units)
		}

		var otherNames []interface{}
		if item.ItemOtherNames != nil {
			json.Unmarshal(item.ItemOtherNames, &otherNames)
		}

		resp = append(resp, fiber.Map{
			"item_id":           item.ItemID,
			"item_default_name": item.ItemDefaultName,
			"item_other_names":  otherNames,
			"type_id":           tID,
			"units":             units,
			"is_active":         item.IsActive,
			"created_at":        item.CreatedAt,
			"updated_at":        item.UpdatedAt,
		})
	}

	return c.Status(200).JSON(fiber.Map{"data": resp})
}

// example query: GET /items/search?keyword=example&limit=10
// example response body for SearchItems:
//
//	{
//	    "data": [
//	        {
//	            "item_id": "item-uuid",
//	            "item_formal_name": "Example Item",
//	            "item_other_names": ["ExItem", "Example"],
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

	typeIDStr := c.Query("typeId")
	limitStr := c.Query("limit", "10")
	parsedLimit, err := strconv.ParseInt(limitStr, 10, 32)
	limit := int32(parsedLimit)
	if err != nil || limit <= 0 {
		limit = 10
	}
	if limit > 100 {
		limit = 100
	}

	var typeID *uuid.UUID
	if typeIDStr != "" {
		parsedTypeID, err := uuid.Parse(typeIDStr)
		if err == nil {
			typeID = &parsedTypeID
		}
	}

	items, err := h.service.SearchItems(context.Background(), keyword, typeID, limit)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Failed to search items"})
	}

	resp := []fiber.Map{}
	for _, item := range items {
		var tID *uuid.UUID
		if item.TypeID.Valid {
			tID = &item.TypeID.UUID
		}

		var units []interface{}
		if item.Units != nil {
			json.Unmarshal(item.Units, &units)
		}

		var otherNames []interface{}
		if item.ItemOtherNames != nil {
			json.Unmarshal(item.ItemOtherNames, &otherNames)
		}

		resp = append(resp, fiber.Map{
			"item_id":           item.ItemID,
			"item_default_name": item.ItemDefaultName,
			"item_other_names":  otherNames,
			"type_id":           tID,
			"units":             units,
			"is_active":         item.IsActive,
			"created_at":        item.CreatedAt,
			"updated_at":        item.UpdatedAt,
		})
	}

	return c.Status(200).JSON(fiber.Map{"data": resp})
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

	var itmID *uuid.UUID
	if unit.ItemID.Valid {
		itmID = &unit.ItemID.UUID
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Unit created and assigned to item successfully",
		"data": fiber.Map{
			"unit_id":            unit.UnitID,
			"item_id":            itmID,
			"unit_name":          unit.UnitName,
			"unit_price_default": unit.UnitPriceDefault,
			"is_active":          unit.IsActive,
			"created_at":         unit.CreatedAt,
			"updated_at":         unit.UpdatedAt,
		},
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

	resp := []fiber.Map{}
	for _, unit := range units {
		var itmID *uuid.UUID
		if unit.ItemID.Valid {
			itmID = &unit.ItemID.UUID
		}
		resp = append(resp, fiber.Map{
			"unit_id":            unit.UnitID,
			"item_id":            itmID,
			"unit_name":          unit.UnitName,
			"unit_price_default": unit.UnitPriceDefault,
			"is_active":          unit.IsActive,
			"created_at":         unit.CreatedAt,
			"updated_at":         unit.UpdatedAt,
		})
	}

	return c.Status(200).JSON(fiber.Map{"data": resp})
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

func (h *ItemHandler) AddItemOtherName(c *fiber.Ctx) error {
	type addOtherNameRequest struct {
		NameString string `json:"nameString"`
	}

	itemID := c.Params("itemId")
	var req addOtherNameRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Required key: nameString"})
	}

	if req.NameString == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing required key: nameString"})
	}

	otherName, err := h.service.CreateItemOtherName(context.Background(), itemID, req.NameString)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Failed to add other name. Verify itemId is a valid UUID"})
	}

	return c.Status(201).JSON(fiber.Map{
		"message": "Other name added successfully",
		"data":    otherName,
	})
}

func (h *ItemHandler) RemoveItemOtherName(c *fiber.Ctx) error {
	otherNameID := c.Params("otherNameId")
	if otherNameID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: otherNameId"})
	}

	err := h.service.DeleteItemOtherName(context.Background(), otherNameID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Failed to remove other name. Verify otherNameId is a valid UUID"})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Other name removed successfully"})
}

func (h *ItemHandler) PatchItem(c *fiber.Ctx) error {
	itemID := c.Params("itemId")
	if itemID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: itemId"})
	}

	body := map[string]json.RawMessage{}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Allowed keys: itemDefaultName, typeId"})
	}

	if len(body) == 0 {
		return c.Status(400).JSON(fiber.Map{"error": "No updatable keys provided. Allowed keys: itemDefaultName, typeId"})
	}

	allowed := map[string]struct{}{
		"itemDefaultName": {},
		"typeId":          {},
	}

	forbidden, unknown := splitPatchKeys(body, allowed)
	if len(forbidden) > 0 {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Keys are not allowed in patch: %s", strings.Join(forbidden, ", "))})
	}
	if len(unknown) > 0 {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Unknown keys in request body: %s", strings.Join(unknown, ", "))})
	}

	input := PatchItemInput{}

	if raw, ok := body["itemDefaultName"]; ok {
		var value string
		if err := json.Unmarshal(raw, &value); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: itemDefaultName (must be string)"})
		}
		if strings.TrimSpace(value) == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: itemDefaultName (must not be empty)"})
		}
		input.SetItemDefaultName = true
		input.ItemDefaultName = value
	}

	if raw, ok := body["typeId"]; ok {
		input.SetTypeID = true
		if string(raw) == "null" {
			input.TypeID = uuid.NullUUID{Valid: false}
		} else {
			var value string
			if err := json.Unmarshal(raw, &value); err != nil {
				return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: typeId (must be UUID string or null)"})
			}

			trimmedValue := strings.TrimSpace(value)
			if trimmedValue == "" {
				input.TypeID = uuid.NullUUID{Valid: false}
			} else {
				parsedTypeID, err := uuid.Parse(trimmedValue)
				if err != nil {
					return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: typeId (must be valid UUID or null)"})
				}
				input.TypeID = uuid.NullUUID{UUID: parsedTypeID, Valid: true}
			}
		}
	}

	itemData, err := h.service.PatchItem(context.Background(), itemID, input)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.Status(404).JSON(fiber.Map{"error": "Item not found"})
		}
		return c.Status(400).JSON(fiber.Map{"error": "Failed to patch item. Please verify itemId/typeId are valid UUIDs and related records exist"})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Item patched successfully",
		"data":    itemData,
	})
}

func (h *ItemHandler) PatchUnit(c *fiber.Ctx) error {
	unitID := c.Params("unitId")
	if unitID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: unitId"})
	}

	body := map[string]json.RawMessage{}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Allowed keys: unitName, unitPriceDefault, itemId(optional)"})
	}

	if len(body) == 0 {
		return c.Status(400).JSON(fiber.Map{"error": "No updatable keys provided. Allowed keys: unitName, unitPriceDefault, itemId(optional)"})
	}

	allowed := map[string]struct{}{
		"unitName":         {},
		"unitPriceDefault": {},
		"itemId":           {},
	}

	forbidden, unknown := splitPatchKeys(body, allowed)
	if len(forbidden) > 0 {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Keys are not allowed in patch: %s", strings.Join(forbidden, ", "))})
	}
	if len(unknown) > 0 {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Unknown keys in request body: %s", strings.Join(unknown, ", "))})
	}

	input := PatchUnitInput{}

	if raw, ok := body["unitName"]; ok {
		var value string
		if err := json.Unmarshal(raw, &value); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: unitName (must be string)"})
		}
		if strings.TrimSpace(value) == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: unitName (must not be empty)"})
		}
		input.SetUnitName = true
		input.UnitName = value
	}

	if raw, ok := body["unitPriceDefault"]; ok {
		var value int64
		if err := json.Unmarshal(raw, &value); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: unitPriceDefault (must be number)"})
		}
		input.SetUnitPriceDefault = true
		input.UnitPriceDefault = value
	}

	if raw, ok := body["itemId"]; ok {
		input.SetItemID = true
		if string(raw) == "null" {
			input.ItemID = uuid.NullUUID{Valid: false}
		} else {
			var value string
			if err := json.Unmarshal(raw, &value); err != nil {
				return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: itemId (must be UUID string or null)"})
			}

			trimmedValue := strings.TrimSpace(value)
			if trimmedValue == "" {
				input.ItemID = uuid.NullUUID{Valid: false}
			} else {
				parsedItemID, err := uuid.Parse(trimmedValue)
				if err != nil {
					return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: itemId (must be valid UUID or null)"})
				}
				input.ItemID = uuid.NullUUID{UUID: parsedItemID, Valid: true}
			}
		}
	}

	unitData, err := h.service.PatchUnit(context.Background(), unitID, input)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.Status(404).JSON(fiber.Map{"error": "Unit not found"})
		}
		return c.Status(400).JSON(fiber.Map{"error": "Failed to patch unit. Please verify unitId/itemId are valid UUIDs and related records exist"})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Unit patched successfully",
		"data":    unitData,
	})
}

func (h *ItemHandler) PatchType(c *fiber.Ctx) error {
	typeID := c.Params("typeId")
	if typeID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: typeId"})
	}

	body := map[string]json.RawMessage{}
	if err := c.BodyParser(&body); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid JSON body. Allowed keys: typeName"})
	}

	if len(body) == 0 {
		return c.Status(400).JSON(fiber.Map{"error": "No updatable keys provided. Allowed keys: typeName"})
	}

	allowed := map[string]struct{}{
		"typeName": {},
	}

	forbidden, unknown := splitPatchKeys(body, allowed)
	if len(forbidden) > 0 {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Keys are not allowed in patch: %s", strings.Join(forbidden, ", "))})
	}
	if len(unknown) > 0 {
		return c.Status(400).JSON(fiber.Map{"error": fmt.Sprintf("Unknown keys in request body: %s", strings.Join(unknown, ", "))})
	}

	input := PatchTypeInput{}

	if raw, ok := body["typeName"]; ok {
		var value string
		if err := json.Unmarshal(raw, &value); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: typeName (must be string)"})
		}
		if strings.TrimSpace(value) == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid value for key: typeName (must not be empty)"})
		}
		input.SetTypeName = true
		input.TypeName = value
	}

	typeData, err := h.service.PatchType(context.Background(), typeID, input)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.Status(404).JSON(fiber.Map{"error": "Type not found"})
		}
		return c.Status(400).JSON(fiber.Map{"error": "Failed to patch type. Please verify typeId is a valid UUID and typeName is unique"})
	}

	return c.Status(200).JSON(fiber.Map{
		"message": "Type patched successfully",
		"data":    typeData,
	})
}

func (h *ItemHandler) DeleteUnit(c *fiber.Ctx) error {
	unitID := c.Params("unitId")
	if unitID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: unitId"})
	}

	err := h.service.DeleteUnit(context.Background(), unitID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Failed to delete unit"})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Unit deleted successfully"})
}

func (h *ItemHandler) DeleteItemOtherName(c *fiber.Ctx) error {
	otherNameID := c.Params("otherNameId")
	if otherNameID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "Missing path param: otherNameId"})
	}

	err := h.service.DeleteItemOtherName(context.Background(), otherNameID)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Failed to delete other name"})
	}

	return c.Status(200).JSON(fiber.Map{"message": "Other name deleted successfully"})
}
