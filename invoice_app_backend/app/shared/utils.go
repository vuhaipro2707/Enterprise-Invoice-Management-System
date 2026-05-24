package shared

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
			fmt.Printf("Error reading ward_map.json: %v\n", err)
			wardMapInstance = make(WardMap)
			return
		}
		if err := json.Unmarshal(data, &wardMapInstance); err != nil {
			fmt.Printf("Error unmarshaling ward_map.json: %v\n", err)
			wardMapInstance = make(WardMap)
		}
	})
	return wardMapInstance
}

// GenerateMidString calculates a lexicographical midpoint between two strings.
// It uses a base-36-like logic (0-9, a-z) to find the middle string.
func GenerateMidString(prev, next string) string {
	const minVal = "00000"
	const maxVal = "zzzzz"

	if prev == "" {
		prev = minVal
	}
	if next == "" {
		next = maxVal
	}

	// Ensure prev < next for midpoint calculation
	if prev >= next {
		return prev + "m"
	}

	res := ""
	i := 0
	for {
		pChar := 0
		if i < len(prev) {
			pChar = charToValue(prev[i])
		}

		nChar := 35 // base 36 (0-9, a-z)
		if i < len(next) {
			nChar = charToValue(next[i])
		}

		if pChar == nChar {
			res += string(valueToChar(pChar))
			i++
			continue
		}

		if nChar-pChar > 1 {
			// There's a gap between characters, take the middle
			mid := (pChar + nChar) / 2
			res += string(valueToChar(mid))
			break
		} else {
			// nChar is pChar + 1, no gap at this index.
			// Add pChar and move to next index to find a gap.
			res += string(valueToChar(pChar))
			i++
			// If we run out of next string characters, we just append a middle value
			if i >= len(next) {
				res += "m" // 'm' is middle of 0-z
				break
			}
		}
	}

	if res <= prev {
		res = prev + "m"
	}
	return res
}

func charToValue(c byte) int {
	if c >= '0' && c <= '9' {
		return int(c - '0')
	}
	if c >= 'a' && c <= 'z' {
		return int(c - 'a' + 10)
	}
	return 0
}

func valueToChar(v int) byte {
	if v >= 0 && v <= 9 {
		return byte(v + '0')
	}
	if v >= 10 && v <= 35 {
		return byte(v - 10 + 'a')
	}
	return '0'
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
