package item

import (
	"context"
	"encoding/json"

	sqlc "invoice_backend/db/sqlc"

	"github.com/google/uuid"
	"github.com/sqlc-dev/pqtype"
)

type ItemService struct {
	Repo *sqlc.Queries
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
