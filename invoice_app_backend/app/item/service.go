package item

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"invoice_backend/app/dbconn"
	sqlc "invoice_backend/db/sqlc"

	"github.com/google/uuid"
	"google.golang.org/genai"
)

type BatchCreateItemPayload struct {
	ItemName   string               `json:"itemName"`
	OtherNames []string             `json:"otherNames"`
	Units      []BatchCreateUnitRow `json:"units"`
}

type BatchCreateUnitRow struct {
	UnitName         string `json:"unitName"`
	Ratio            int64  `json:"ratio"`
	IsBaseUnit       bool   `json:"isBaseUnit"`
	UnitPriceDefault *int64 `json:"unitPriceDefault"`
}

type ItemService struct {
	Repo        *sqlc.Queries
	genaiClient *genai.Client
	genaiConfig *genai.GenerateContentConfig
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
	SetRatio            bool
	Ratio               int64
	SetIsBaseUnit       bool
	IsBaseUnit          bool
}

type PatchTypeInput struct {
	SetTypeName bool
	TypeName    string
}

func NewItemService(repo *sqlc.Queries, genaiClient *genai.Client, genaiConfig *genai.GenerateContentConfig) *ItemService {
	s := &ItemService{
		Repo:        repo,
		genaiClient: genaiClient,
		genaiConfig: genaiConfig,
	}

	return s
}

func (s *ItemService) CreateType(ctx context.Context, typeName string) (sqlc.Type, error) {
	return s.Repo.CreateType(ctx, typeName)
}

func (s *ItemService) GetTypes(ctx context.Context) ([]sqlc.Type, error) {
	return s.Repo.ListTypes(ctx)
}

func (s *ItemService) CreateItem(ctx context.Context, itemDefaultName string, itemOtherNames []string, typeID string) (sqlc.Item, error) {
	if dbconn.DB == nil {
		return sqlc.Item{}, errors.New("database connection pool is uninitialized")
	}

	tx, err := dbconn.DB.BeginTx(ctx, nil)
	if err != nil {
		return sqlc.Item{}, err
	}
	defer tx.Rollback()

	qTx := s.Repo.WithTx(tx)

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

	item, err := qTx.CreateItem(ctx, params)
	if err != nil {
		return sqlc.Item{}, err
	}

	// Insert other names
	for _, name := range itemOtherNames {
		_, err := qTx.CreateItemOtherName(ctx, sqlc.CreateItemOtherNameParams{
			ItemID:     item.ItemID,
			NameString: name,
		})
		if err != nil {
			return sqlc.Item{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return sqlc.Item{}, err
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

func (s *ItemService) CreateUnitForItem(ctx context.Context, itemID string, unitName string, unitPriceDefault *int64, ratio int64, isBaseUnit bool) (sqlc.Unit, error) {
	parsedItemID, err := uuid.Parse(itemID)
	if err != nil {
		return sqlc.Unit{}, err
	}

	createParams := sqlc.CreateUnitParams{
		UnitName:   unitName,
		ItemID:     uuid.NullUUID{UUID: parsedItemID, Valid: true},
		Ratio:      ratio,
		IsBaseUnit: isBaseUnit,
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
	if dbconn.DB == nil {
		return sqlc.Unit{}, errors.New("database connection pool is uninitialized")
	}

	tx, err := dbconn.DB.BeginTx(ctx, nil)
	if err != nil {
		return sqlc.Unit{}, err
	}
	defer tx.Rollback()

	qTx := s.Repo.WithTx(tx)

	parsedUnitID, err := uuid.Parse(unitID)
	if err != nil {
		return sqlc.Unit{}, err
	}

	// 1. Get the existing unit to know is_base_unit and item_id
	existingUnit, err := qTx.GetUnitByID(ctx, parsedUnitID)
	if err != nil {
		return sqlc.Unit{}, err
	}

	if !existingUnit.ItemID.Valid {
		return sqlc.Unit{}, errors.New("unit has no associated item")
	}

	// Check if this unit is a secondary unit and we are setting a new price
	if !existingUnit.IsBaseUnit && (input.SetUnitPriceDefault || input.SetRatio) {
		// Determine the ratio to use (new or existing)
		ratio := existingUnit.Ratio
		if input.SetRatio {
			ratio = input.Ratio
		}
		if ratio <= 0 {
			ratio = 1
		}

		if input.SetUnitPriceDefault {
			// Find the base unit for this item
			var baseUnit sqlc.Unit
			units, getErr := qTx.ListUnits(ctx) // list all units to find base unit for this item
			if getErr == nil {
				for _, u := range units {
					if u.ItemID.Valid && u.ItemID.UUID == existingUnit.ItemID.UUID && u.IsBaseUnit {
						baseUnit = u
						break
					}
				}
			}

			if baseUnit.UnitID == uuid.Nil {
				return sqlc.Unit{}, errors.New("base unit not found for this item")
			}

			// Calculate new base price
			newBasePrice := int64(math.Round(float64(input.UnitPriceDefault) / float64(ratio)))

			// If also updating ratio on the secondary unit, do that first so it uses the correct ratio
			if input.SetRatio || input.SetUnitName {
				params := sqlc.PatchUnitParams{
					UnitID:        parsedUnitID,
					SetUnitName:   input.SetUnitName,
					UnitName:      input.UnitName,
					SetRatio:      input.SetRatio,
					Ratio:         input.Ratio,
					SetIsBaseUnit: input.SetIsBaseUnit,
					IsBaseUnit:    input.IsBaseUnit,
				}
				_, patchErr := qTx.PatchUnit(ctx, params)
				if patchErr != nil {
					return sqlc.Unit{}, patchErr
				}
			}

			// Update the base unit's price
			baseParams := sqlc.PatchUnitParams{
				UnitID:              baseUnit.UnitID,
				SetUnitPriceDefault: true,
				UnitPriceDefault:    newBasePrice,
			}
			_, patchErr := qTx.PatchUnit(ctx, baseParams)
			if patchErr != nil {
				return sqlc.Unit{}, patchErr
			}

			if err := tx.Commit(); err != nil {
				return sqlc.Unit{}, err
			}

			// Return the updated unit (refetched to get the precise value from database trigger)
			return s.Repo.GetUnitByID(ctx, parsedUnitID)
		}
	}

	// Default flow (e.g. updating base unit itself, or just unit name, or ratio without changing price)
	params := sqlc.PatchUnitParams{
		UnitID:              parsedUnitID,
		SetUnitName:         input.SetUnitName,
		UnitName:            input.UnitName,
		SetUnitPriceDefault: input.SetUnitPriceDefault,
		UnitPriceDefault:    input.UnitPriceDefault,
		SetItemID:           input.SetItemID,
		ItemID:              input.ItemID,
		SetRatio:            input.SetRatio,
		Ratio:               input.Ratio,
		SetIsBaseUnit:       input.SetIsBaseUnit,
		IsBaseUnit:          input.IsBaseUnit,
	}

	res, err := qTx.PatchUnit(ctx, params)
	if err != nil {
		return sqlc.Unit{}, err
	}

	if err := tx.Commit(); err != nil {
		return sqlc.Unit{}, err
	}

	return res, nil
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

func (s *ItemService) BatchCreateItems(ctx context.Context, typeID string, payloads []BatchCreateItemPayload) error {
	if dbconn.DB == nil {
		return errors.New("database connection pool is uninitialized")
	}

	// Bắt đầu transaction
	tx, err := dbconn.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Khởi tạo Queries với transaction
	qTx := s.Repo.WithTx(tx)

	var parsedTypeID uuid.NullUUID
	if typeID != "" {
		tid, err := uuid.Parse(typeID)
		if err != nil {
			return errors.New("invalid typeId UUID")
		}
		parsedTypeID = uuid.NullUUID{UUID: tid, Valid: true}
	}

	for _, p := range payloads {
		if strings.TrimSpace(p.ItemName) == "" {
			return errors.New("itemName must not be empty")
		}

		// 1. Create item
		itemParams := sqlc.CreateItemParams{
			ItemDefaultName: p.ItemName,
			TypeID:          parsedTypeID,
		}
		item, err := qTx.CreateItem(ctx, itemParams)
		if err != nil {
			return err
		}

		// 2. Create other names
		for _, oName := range p.OtherNames {
			trimmed := strings.TrimSpace(oName)
			if trimmed == "" {
				continue
			}
			_, err = qTx.CreateItemOtherName(ctx, sqlc.CreateItemOtherNameParams{
				ItemID:     item.ItemID,
				NameString: trimmed,
			})
			if err != nil {
				return err
			}
		}

		// 3. Sort units so isBaseUnit = true is created FIRST!
		units := p.Units
		sort.Slice(units, func(i, j int) bool {
			return units[i].IsBaseUnit && !units[j].IsBaseUnit
		})

		// 4. Create units
		for _, u := range units {
			unitName := strings.TrimSpace(u.UnitName)
			if unitName == "" {
				continue
			}

			// Viết hoa chữ cái đầu tiên của đơn vị
			if len(unitName) > 0 {
				unitName = strings.ToUpper(string(unitName[0])) + unitName[1:]
			}

			unitParams := sqlc.CreateUnitParams{
				UnitName:   unitName,
				ItemID:     uuid.NullUUID{UUID: item.ItemID, Valid: true},
				Ratio:      u.Ratio,
				IsBaseUnit: u.IsBaseUnit,
			}
			if u.UnitPriceDefault != nil {
				unitParams.UnitPriceDefault = *u.UnitPriceDefault
			}
			_, err = qTx.CreateUnit(ctx, unitParams)
			if err != nil {
				return err
			}
		}
	}

	// Commit transaction
	return tx.Commit()
}

// initContextCache attempts to create a context cache on the Gemini server for our static instructions/tools.
// It optimizes cost/quotas by checking for existing valid caches with the same DisplayName before creating a new one.
func (s *ItemService) initContextCache(ctx context.Context) {
	if s.genaiClient == nil || s.genaiConfig == nil {
		return
	}

	modelName := "gemini-3.1-flash-lite"
	displayName := "item_suggestions_static_instructions"

	// 1. Kiểm tra danh sách cache hiện tại để tìm cache trùng DisplayName và chưa hết hạn
	page, err := s.genaiClient.Caches.List(ctx, &genai.ListCachedContentsConfig{PageSize: 50})
	if err == nil {
		now := time.Now()
		for _, item := range page.Items {
			if item != nil && item.DisplayName == displayName && item.ExpireTime.After(now) && strings.Contains(item.Model, modelName) {
				// Tái sử dụng cache hiện tại, tránh tạo mới vô ích mỗi khi hot reload
				s.genaiConfig.CachedContent = item.Name
				fmt.Printf("[GenAI] Reusing existing valid Context Cache! Name: %s, Expires at: %s\n", item.Name, item.ExpireTime.Format(time.RFC3339))
				return
			}
		}
	}

	// 2. Chỉ tạo cache mới khi không tìm thấy cache cũ còn hạn sử dụng
	cacheConfig := &genai.CreateCachedContentConfig{
		DisplayName:       displayName,
		SystemInstruction: s.genaiConfig.SystemInstruction,
		Tools:             s.genaiConfig.Tools,
		TTL:               30 * time.Minute,
	}

	cachedContent, err := s.genaiClient.Caches.Create(ctx, modelName, cacheConfig)
	if err != nil {
		// Log gracefully, context caching requires >= 32,768 tokens, ours is smaller (~1500 tokens).
		fmt.Printf("[GenAI] Context Caching not active: %v (Gracefully falling back to normal prompt processing)\n", err)
		return
	}

	s.genaiConfig.CachedContent = cachedContent.Name
	fmt.Printf("[GenAI] Context Caching successfully activated! Cache Name: %s\n", cachedContent.Name)
}

// GenerateItemAISuggestions queries the Gemini model (with search tool and cached content optimization if active)
// to fetch structured retail conversions and options.
func (s *ItemService) GenerateItemAISuggestions(ctx context.Context, keyword string) (string, error) {
	if s.genaiClient == nil || s.genaiConfig == nil {
		return "", errors.New("Gemini GenAI service is not initialized on startup")
	}

	// Nếu chưa có cache, khởi tạo/tìm kiếm cache trên server trước
	if s.genaiConfig.CachedContent == "" {
		// fmt.Println("[GenAI] No cache active. Initializing context cache...")
		s.initContextCache(ctx)
	}

	// Clone config parameters correctly based on whether we use Context Cache
	reqConfig := &genai.GenerateContentConfig{}

	useCache := s.genaiConfig.CachedContent != ""
	if useCache {
		reqConfig.CachedContent = s.genaiConfig.CachedContent
		// fmt.Printf("[GenAI] Cache status: ACTIVE | Reusing context cache: '%s'\n", s.genaiConfig.CachedContent)
	} else {
		reqConfig.SystemInstruction = s.genaiConfig.SystemInstruction
		reqConfig.Tools = s.genaiConfig.Tools
		// fmt.Println("[GenAI] Cache status: INACTIVE | Reason: Static instructions and tools are below Gemini's 32,768 minimum token threshold for server-side caching or cache creation failed. Falling back to direct prompt execution.")
	}

	// fmt.Printf("[GenAI] Querying Gemini for keyword: '%s' | useCache: %v | CachedContent: '%s'\n", keyword, useCache, s.genaiConfig.CachedContent)

	resp, err := s.genaiClient.Models.GenerateContent(ctx, "gemini-3.1-flash-lite", genai.Text(keyword), reqConfig)
	if err != nil {
		// Tự động hồi phục ĐỒNG BỘ (Synchronous Self-healing) nếu cache bị hết hạn hoặc không tìm thấy trên server
		isCacheError := strings.Contains(err.Error(), "not found") ||
			strings.Contains(err.Error(), "404") ||
			strings.Contains(err.Error(), "400") ||
			strings.Contains(err.Error(), "cache") ||
			strings.Contains(err.Error(), "expired")

		if useCache && isCacheError {
			fmt.Printf("[GenAI] Cache expired or invalid (err: %v). Attempting to recreate cache synchronously...\n", err)

			// Xóa cache cũ
			s.genaiConfig.CachedContent = ""

			// Gọi tạo cache mới ĐỒNG BỘ (chờ khoảng 2-3s để ghi cache, chi phí 1.0)
			s.initContextCache(ctx)

			// Chuẩn bị cấu hình mới sử dụng cache vừa được tạo lập
			retryConfig := &genai.GenerateContentConfig{}
			if s.genaiConfig.CachedContent != "" {
				retryConfig.CachedContent = s.genaiConfig.CachedContent
			} else {
				// Fallback an toàn nếu tạo cache vẫn thất bại
				retryConfig.SystemInstruction = s.genaiConfig.SystemInstruction
				retryConfig.Tools = s.genaiConfig.Tools
			}

			// fmt.Printf("[GenAI] Retrying Gemini query | new useCache: %v | new CachedContent: '%s'\n", s.genaiConfig.CachedContent != "", s.genaiConfig.CachedContent)

			resp, err = s.genaiClient.Models.GenerateContent(ctx, "gemini-3.1-flash-lite", genai.Text(keyword), retryConfig)
			if err != nil {
				return "", fmt.Errorf("failed to query Gemini model after synchronous cache rebuild: %w", err)
			}
		} else {
			return "", fmt.Errorf("failed to query Gemini model: %w", err)
		}
	}

	cachedContentLog := s.genaiConfig.CachedContent
	if cachedContentLog == "" {
		cachedContentLog = "none"
	}
	if resp.UsageMetadata != nil {
		fmt.Printf("[GenAI] Success | CachedContent: '%s' | keyword: '%s' | Prompt: %d | Candidates: %d | Total: %d | Cached: %d\n",
			cachedContentLog,
			keyword,
			resp.UsageMetadata.PromptTokenCount,
			resp.UsageMetadata.CandidatesTokenCount,
			resp.UsageMetadata.TotalTokenCount,
			resp.UsageMetadata.CachedContentTokenCount)
	} else {
		fmt.Printf("[GenAI] Success | CachedContent: '%s' | keyword: '%s'\n", cachedContentLog, keyword)
	}

	if len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil || len(resp.Candidates[0].Content.Parts) == 0 {
		return "", errors.New("Gemini returned an empty response. Please try again with a different keyword")
	}

	rawText := resp.Candidates[0].Content.Parts[0].Text
	cleanJSON := rawText

	if strings.Contains(cleanJSON, "```json") {
		cleanJSON = strings.Split(cleanJSON, "```json")[1]
		cleanJSON = strings.Split(cleanJSON, "```")[0]
	} else if strings.Contains(cleanJSON, "```") {
		cleanJSON = strings.Split(cleanJSON, "```")[1]
		cleanJSON = strings.Split(cleanJSON, "```")[0]
	}
	cleanJSON = strings.TrimSpace(cleanJSON)

	var testMap map[string]interface{}
	if err := json.Unmarshal([]byte(cleanJSON), &testMap); err != nil {
		return "", fmt.Errorf("failed to parse Gemini response as JSON: %w (raw response: %s)", err, rawText)
	}

	return cleanJSON, nil
}

func (s *ItemService) DeleteItem(ctx context.Context, itemID string) error {
	parsedUUID, err := uuid.Parse(itemID)
	if err != nil {
		return err
	}
	return s.Repo.DeleteItem(ctx, parsedUUID)
}

func (s *ItemService) RestoreItem(ctx context.Context, itemID string) error {
	parsedUUID, err := uuid.Parse(itemID)
	if err != nil {
		return err
	}
	return s.Repo.RestoreItem(ctx, parsedUUID)
}

func (s *ItemService) GetDeletedItems(ctx context.Context) ([]sqlc.ListDeletedItemsRow, error) {
	return s.Repo.ListDeletedItems(ctx)
}
