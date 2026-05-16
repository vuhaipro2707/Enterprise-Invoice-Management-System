package item

import (
	"context"

	sqlc "invoice_backend/db/sqlc"

	"github.com/google/uuid"
)

type ItemService struct {
	Repo *sqlc.Queries
}

type PatchItemInput struct {
	SetItemDefaultName bool
	ItemDefaultName    string
	SetTypeID          bool
	TypeID             uuid.NullUUID
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

func (s *ItemService) CreateItem(ctx context.Context, itemDefaultName string, itemOtherNames []string, typeID string) (sqlc.Item, error) {
	params := sqlc.CreateItemParams{
		ItemDefaultName: itemDefaultName,
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

	// Insert other names
	for _, name := range itemOtherNames {
		_, err := s.Repo.CreateItemOtherName(ctx, sqlc.CreateItemOtherNameParams{
			ItemID:     item.ItemID,
			NameString: name,
		})
		if err != nil {
			// TODO: In a real app, you might want a transaction here or handle partial success
			return item, err
		}
	}

	return item, nil
}

func (s *ItemService) GetItems(ctx context.Context) ([]sqlc.ListItemsRow, error) {
	return s.Repo.ListItems(ctx)
}

func (s *ItemService) GetItemsFiltered(ctx context.Context, typeID *uuid.UUID, limit int32, offset int32, sortBy string, sortOrder string) ([]sqlc.ListItemsFilteredRow, error) {
	params := sqlc.ListItemsFilteredParams{
		LimitVal:  limit,
		OffsetVal: offset,
		SortBy:    sortBy,
		SortOrder: sortOrder,
	}
	if typeID != nil {
		params.TypeID = uuid.NullUUID{UUID: *typeID, Valid: true}
	}
	return s.Repo.ListItemsFiltered(ctx, params)
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

func (s *ItemService) SearchItems(ctx context.Context, keyword string, typeID *uuid.UUID, limit int32) ([]sqlc.SearchItemsRow, error) {
	if keyword == "" {
		return []sqlc.SearchItemsRow{}, nil
	}

	// Default limit to 10 if not specified or invalid
	if limit <= 0 || limit > 100 {
		limit = 10
	}

	params := sqlc.SearchItemsParams{
		Keyword:  keyword,
		LimitVal: limit,
	}

	if typeID != nil {
		params.TypeID = uuid.NullUUID{UUID: *typeID, Valid: true}
	}

	return s.Repo.SearchItems(ctx, params)
}

func (s *ItemService) CreateItemOtherName(ctx context.Context, itemID string, nameString string) (sqlc.ItemOtherName, error) {
	parsedItemID, err := uuid.Parse(itemID)
	if err != nil {
		return sqlc.ItemOtherName{}, err
	}

	return s.Repo.CreateItemOtherName(ctx, sqlc.CreateItemOtherNameParams{
		ItemID:     parsedItemID,
		NameString: nameString,
	})
}

func (s *ItemService) DeleteItemOtherName(ctx context.Context, otherNameID string) error {
	parsedID, err := uuid.Parse(otherNameID)
	if err != nil {
		return err
	}
	return s.Repo.DeleteItemOtherName(ctx, parsedID)
}

func (s *ItemService) PatchItem(ctx context.Context, itemID string, input PatchItemInput) (sqlc.Item, error) {
	parsedItemID, err := uuid.Parse(itemID)
	if err != nil {
		return sqlc.Item{}, err
	}

	params := sqlc.PatchItemParams{
		ItemID:             parsedItemID,
		SetItemDefaultName: input.SetItemDefaultName,
		ItemDefaultName:    input.ItemDefaultName,
		SetTypeID:          input.SetTypeID,
		TypeID:             input.TypeID,
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

func (s *ItemService) DeleteUnit(ctx context.Context, unitID string) error {
	parsedUUID, err := uuid.Parse(unitID)
	if err != nil {
		return err
	}
	return s.Repo.DeleteUnit(ctx, parsedUUID)
}
