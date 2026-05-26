package globalsettings

import (
	"context"
	"encoding/json"
	sqlc "invoice_backend/db/sqlc"
)

type GlobalSettingsService struct {
	Repo *sqlc.Queries
}

func NewGlobalSettingsService(repo *sqlc.Queries) *GlobalSettingsService {
	return &GlobalSettingsService{
		Repo: repo,
	}
}

func (s *GlobalSettingsService) GetSettings(ctx context.Context) (sqlc.GetGlobalSettingsRow, error) {
	return s.Repo.GetGlobalSettings(ctx)
}

func (s *GlobalSettingsService) UpdateSettings(ctx context.Context, config json.RawMessage) (sqlc.UpdateGlobalSettingsRow, error) {
	return s.Repo.UpdateGlobalSettings(ctx, config)
}
