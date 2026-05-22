package pricelist

import (
	"context"
	"database/sql"
	"errors"
	"invoice_backend/app/dbconn"
	sqlc "invoice_backend/db/sqlc"
	"time"

	"github.com/google/uuid"
)

type PriceListService struct {
	Repo *sqlc.Queries
}

func NewPriceListService(repo *sqlc.Queries) *PriceListService {
	return &PriceListService{Repo: repo}
}

type CreatePriceListInput struct {
	Description string           `json:"description"`
	BuyerID     string           `json:"buyerId"`
	Items       []PriceItemInput `json:"items"`
}

type PriceItemInput struct {
	ItemID          string `json:"itemId"`
	UnitID          string `json:"unitId"`
	UnitPriceCustom int64  `json:"unitPriceCustom"`
}

func (s *PriceListService) CreatePriceList(ctx context.Context, input CreatePriceListInput) (sqlc.CustomerPriceList, error) {
	if dbconn.DB == nil {
		return sqlc.CustomerPriceList{}, errors.New("database connection pool is uninitialized")
	}

	tx, err := dbconn.DB.BeginTx(ctx, nil)
	if err != nil {
		return sqlc.CustomerPriceList{}, err
	}
	defer tx.Rollback()

	qTx := s.Repo.WithTx(tx)

	var buyerUUID uuid.NullUUID
	if input.BuyerID != "" {
		bid, err := uuid.Parse(input.BuyerID)
		if err != nil {
			return sqlc.CustomerPriceList{}, errors.New("invalid buyerId UUID")
		}
		buyerUUID = uuid.NullUUID{UUID: bid, Valid: true}
	}

	cpl, err := qTx.CreateCustomerPriceList(ctx, sqlc.CreateCustomerPriceListParams{
		Description: input.Description,
		BuyerID:     buyerUUID,
	})
	if err != nil {
		return sqlc.CustomerPriceList{}, err
	}

	for _, item := range input.Items {
		itemUUID, err := uuid.Parse(item.ItemID)
		if err != nil {
			return sqlc.CustomerPriceList{}, errors.New("invalid itemId UUID: " + item.ItemID)
		}

		var unitUUID uuid.NullUUID
		if item.UnitID != "" {
			uid, err := uuid.Parse(item.UnitID)
			if err != nil {
				return sqlc.CustomerPriceList{}, errors.New("invalid unitId UUID: " + item.UnitID)
			}
			unitUUID = uuid.NullUUID{UUID: uid, Valid: true}
		}

		_, err = qTx.CreateCustomerItemPrice(ctx, sqlc.CreateCustomerItemPriceParams{
			CustomerPriceListID: uuid.NullUUID{UUID: cpl.CustomerPriceListID, Valid: true},
			ItemID:              uuid.NullUUID{UUID: itemUUID, Valid: true},
			UnitID:              unitUUID,
			UnitPriceCustom:     item.UnitPriceCustom,
		})
		if err != nil {
			return sqlc.CustomerPriceList{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return sqlc.CustomerPriceList{}, err
	}

	return cpl, nil
}

func (s *PriceListService) GetPriceListByID(ctx context.Context, id string) (sqlc.GetCustomerPriceListByIDRow, error) {
	parsedID, err := uuid.Parse(id)
	if err != nil {
		return sqlc.GetCustomerPriceListByIDRow{}, err
	}
	return s.Repo.GetCustomerPriceListByID(ctx, parsedID)
}

func (s *PriceListService) ListPriceLists(ctx context.Context, buyerId string, keyword string, limit, offset int32, sortBy, sortOrder string, startDate, endDate *time.Time) ([]sqlc.ListCustomerPriceListsFilteredRow, error) {
	params := sqlc.ListCustomerPriceListsFilteredParams{
		LimitVal:  limit,
		OffsetVal: offset,
		SortBy:    sortBy,
		SortOrder: sortOrder,
	}

	if buyerId != "" {
		bid, err := uuid.Parse(buyerId)
		if err == nil {
			params.BuyerID = uuid.NullUUID{UUID: bid, Valid: true}
		}
	}

	if keyword != "" {
		params.BuyerName = sql.NullString{String: keyword, Valid: true}
	}

	if startDate != nil {
		params.StartDate = sql.NullTime{Time: *startDate, Valid: true}
	}

	if endDate != nil {
		params.EndDate = sql.NullTime{Time: *endDate, Valid: true}
	}

	return s.Repo.ListCustomerPriceListsFiltered(ctx, params)
}

func (s *PriceListService) UpdatePriceList(ctx context.Context, id string, input CreatePriceListInput) (sqlc.CustomerPriceList, error) {
	if dbconn.DB == nil {
		return sqlc.CustomerPriceList{}, errors.New("database connection pool is uninitialized")
	}

	parsedID, err := uuid.Parse(id)
	if err != nil {
		return sqlc.CustomerPriceList{}, err
	}

	tx, err := dbconn.DB.BeginTx(ctx, nil)
	if err != nil {
		return sqlc.CustomerPriceList{}, err
	}
	defer tx.Rollback()

	qTx := s.Repo.WithTx(tx)

	var buyerUUID uuid.NullUUID
	if input.BuyerID != "" {
		bid, err := uuid.Parse(input.BuyerID)
		if err != nil {
			return sqlc.CustomerPriceList{}, errors.New("invalid buyerId UUID")
		}
		buyerUUID = uuid.NullUUID{UUID: bid, Valid: true}
	}

	cpl, err := qTx.UpdateCustomerPriceList(ctx, sqlc.UpdateCustomerPriceListParams{
		CustomerPriceListID: parsedID,
		Description:         input.Description,
		BuyerID:             buyerUUID,
	})
	if err != nil {
		return sqlc.CustomerPriceList{}, err
	}

	err = qTx.DeleteCustomerItemPricesByPriceListID(ctx, uuid.NullUUID{UUID: parsedID, Valid: true})
	if err != nil {
		return sqlc.CustomerPriceList{}, err
	}

	for _, item := range input.Items {
		itemUUID, err := uuid.Parse(item.ItemID)
		if err != nil {
			return sqlc.CustomerPriceList{}, errors.New("invalid itemId UUID: " + item.ItemID)
		}

		var unitUUID uuid.NullUUID
		if item.UnitID != "" {
			uid, err := uuid.Parse(item.UnitID)
			if err != nil {
				return sqlc.CustomerPriceList{}, errors.New("invalid unitId UUID: " + item.UnitID)
			}
			unitUUID = uuid.NullUUID{UUID: uid, Valid: true}
		}

		_, err = qTx.CreateCustomerItemPrice(ctx, sqlc.CreateCustomerItemPriceParams{
			CustomerPriceListID: uuid.NullUUID{UUID: parsedID, Valid: true},
			ItemID:              uuid.NullUUID{UUID: itemUUID, Valid: true},
			UnitID:              unitUUID,
			UnitPriceCustom:     item.UnitPriceCustom,
		})
		if err != nil {
			return sqlc.CustomerPriceList{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return sqlc.CustomerPriceList{}, err
	}

	return cpl, nil
}

func (s *PriceListService) DeletePriceList(ctx context.Context, id string) error {
	parsedID, err := uuid.Parse(id)
	if err != nil {
		return err
	}
	return s.Repo.DeleteCustomerPriceList(ctx, parsedID)
}
