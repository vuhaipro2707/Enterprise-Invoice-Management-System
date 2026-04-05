package item

import (
	"context"
	"database/sql"
	"encoding/json"

	sqlc "invoice_backend/db/sqlc"

	"github.com/google/uuid"
	"github.com/sqlc-dev/pqtype"
)

type ItemService struct {
	Repo *sqlc.Queries
}

type PatchItemInput struct {
	SetItemFormalName bool
	ItemFormalName    string
	SetItemShortNames bool
	ItemShortNamesSet bool
	ItemShortNames    []byte
	SetTypeID         bool
	TypeID            uuid.NullUUID
}

type PatchUnitInput struct {
	SetUnitName         bool
	UnitName            string
	SetUnitPriceDefault bool
	UnitPriceDefault    int64
	SetItemID           bool
	ItemID              uuid.NullUUID
}

type PatchTypeInput struct {
	SetTypeName bool
	TypeName    string
}

func NewItemService(repo *sqlc.Queries) *ItemService {
	return &ItemService{Repo: repo}
}

func (s *ItemService) CreateType(ctx context.Context, typeName string) (sqlc.Type, error) {
	return s.Repo.CreateType(ctx, typeName)
}

func (s *ItemService) GetTypes(ctx context.Context) ([]sqlc.Type, error) {
	return s.Repo.ListTypes(ctx)
}

func (s *ItemService) CreateItem(ctx context.Context, itemFormalName string, itemShortNames []string, typeID string) (sqlc.Item, error) {
	shortNamesJSON, err := json.Marshal(itemShortNames)
	if err != nil {
		return sqlc.Item{}, err
	}

	params := sqlc.CreateItemParams{
		ItemFormalName: itemFormalName,
		ItemShortNames: pqtype.NullRawMessage{RawMessage: shortNamesJSON, Valid: true},
	}

	if typeID != "" {
		parsedTypeID, parseErr := uuid.Parse(typeID)
		if parseErr != nil {
			return sqlc.Item{}, parseErr
		}
		params.TypeID = uuid.NullUUID{UUID: parsedTypeID, Valid: true}
	}

	item, err := s.Repo.CreateItem(ctx, params)
	if err != nil {
		return sqlc.Item{}, err
	}

	return item, nil
}

func (s *ItemService) GetItems(ctx context.Context) ([]sqlc.Item, error) {
	return s.Repo.ListItems(ctx)
}

func (s *ItemService) CreateUnitForItem(ctx context.Context, itemID string, unitName string, unitPriceDefault *int64) (sqlc.Unit, error) {
	parsedItemID, err := uuid.Parse(itemID)
	if err != nil {
		return sqlc.Unit{}, err
	}

	createParams := sqlc.CreateUnitParams{
		UnitName: unitName,
		ItemID:   uuid.NullUUID{UUID: parsedItemID, Valid: true},
	}

	if unitPriceDefault != nil {
		createParams.UnitPriceDefault = *unitPriceDefault
	}

	return s.Repo.CreateUnit(ctx, createParams)
}

func (s *ItemService) GetUnits(ctx context.Context) ([]sqlc.Unit, error) {
	return s.Repo.ListUnits(ctx)
}

func (s *ItemService) SearchItems(ctx context.Context, keyword string, limit int32) ([]sqlc.Item, error) {
	if keyword == "" {
		return []sqlc.Item{}, nil
	}

	// Default limit to 10 if not specified or invalid
	if limit <= 0 || limit > 100 {
		limit = 10
	}

	params := sqlc.SearchItemsParams{
		Column1: sql.NullString{String: keyword, Valid: true},
		Limit:   limit,
	}

	return s.Repo.SearchItems(ctx, params)
}

func (s *ItemService) PatchItem(ctx context.Context, itemID string, input PatchItemInput) (sqlc.Item, error) {
	parsedItemID, err := uuid.Parse(itemID)
	if err != nil {
		return sqlc.Item{}, err
	}

	params := sqlc.PatchItemParams{
		ItemID:            parsedItemID,
		SetItemFormalName: input.SetItemFormalName,
		ItemFormalName:    input.ItemFormalName,
		SetItemShortNames: input.SetItemShortNames,
		ItemShortNames:    pqtype.NullRawMessage{RawMessage: input.ItemShortNames, Valid: input.ItemShortNamesSet},
		SetTypeID:         input.SetTypeID,
		TypeID:            input.TypeID,
	}

	return s.Repo.PatchItem(ctx, params)
}

func (s *ItemService) PatchUnit(ctx context.Context, unitID string, input PatchUnitInput) (sqlc.Unit, error) {
	parsedUnitID, err := uuid.Parse(unitID)
	if err != nil {
		return sqlc.Unit{}, err
	}

	params := sqlc.PatchUnitParams{
		UnitID:              parsedUnitID,
		SetUnitName:         input.SetUnitName,
		UnitName:            input.UnitName,
		SetUnitPriceDefault: input.SetUnitPriceDefault,
		UnitPriceDefault:    input.UnitPriceDefault,
		SetItemID:           input.SetItemID,
		ItemID:              input.ItemID,
	}

	return s.Repo.PatchUnit(ctx, params)
}

func (s *ItemService) PatchType(ctx context.Context, typeID string, input PatchTypeInput) (sqlc.Type, error) {
	parsedTypeID, err := uuid.Parse(typeID)
	if err != nil {
		return sqlc.Type{}, err
	}

	params := sqlc.PatchTypeParams{
		TypeID:      parsedTypeID,
		SetTypeName: input.SetTypeName,
		TypeName:    input.TypeName,
	}

	return s.Repo.PatchType(ctx, params)
}
