package invoice

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync"
)

type WardMap map[string]map[string]string

var (
	wardMapInstance WardMap
	wardMapOnce     sync.Once
)

func GetWardMap() WardMap {
	wardMapOnce.Do(func() {
		data, err := os.ReadFile("ward_map.json")
		if err != nil {
			return
		}
		json.Unmarshal(data, &wardMapInstance)
	})
	return wardMapInstance
}

// NormalizeVietnamese removes common prefixes and converts to lowercase for fuzzy matching
func NormalizeVietnamese(s string) string {
	s = strings.ToLower(s)
	s = strings.ReplaceAll(s, "thành phố ", "")
	s = strings.ReplaceAll(s, "tỉnh ", "")
	s = strings.ReplaceAll(s, "quận ", "")
	s = strings.ReplaceAll(s, "huyện ", "")
	s = strings.ReplaceAll(s, "thị xã ", "")
	s = strings.ReplaceAll(s, "phường ", "")
	s = strings.ReplaceAll(s, "xã ", "")
	s = strings.ReplaceAll(s, "đường ", "")
	return strings.TrimSpace(s)
}

func EnrichAddress(fullAddress string) string {
	wm := GetWardMap()
	if wm == nil {
		return fullAddress
	}

	parts := strings.Split(fullAddress, ", ")
	if len(parts) < 2 {
		return fullAddress
	}

	// Try to find City and Ward from parts
	// Google common format: [Number/Street], [Ward/District], [City], [Country]
	// Example: 26 Đường Cao Văn Lầu, Bình Tiên, Hồ Chí Minh, Việt Nam

	for cityKey, wards := range wm {
		normCityKey := NormalizeVietnamese(cityKey)

		// Check if any part matches the city
		cityIdx := -1
		for i, part := range parts {
			if strings.Contains(NormalizeVietnamese(part), normCityKey) {
				cityIdx = i
				break
			}
		}

		if cityIdx != -1 {
			// Look for ward in parts BEFORE the city
			for i := 0; i < cityIdx; i++ {
				normPart := NormalizeVietnamese(parts[i])

				for wardKey, districtValue := range wards {
					normWardKey := NormalizeVietnamese(wardKey)

					if normPart == normWardKey {
						// Found match! Insert district info
						// Format: Part ("District"), ...
						parts[i] = fmt.Sprintf("%s (%s)", parts[i], districtValue)
						return strings.Join(parts, ", ")
					}
				}
			}
		}
	}

	return fullAddress
}
