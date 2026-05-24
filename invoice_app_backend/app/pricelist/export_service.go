package pricelist

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/jung-kurt/gofpdf/v2"
	"github.com/xuri/excelize/v2"
)

// getStringValue safely extracts and dereferences string pointers or standard interfaces to string.
func getStringValue(val interface{}) string {
	if val == nil {
		return ""
	}
	switch v := val.(type) {
	case string:
		return v
	case *string:
		if v == nil {
			return ""
		}
		return *v
	default:
		return fmt.Sprintf("%v", v)
	}
}

// removeDiacritics converts accented Vietnamese characters to plain ASCII (retains for safe filenames).
func removeDiacritics(str string) string {
	coverted := str
	replacements := []struct {
		from string
		to   string
	}{
		{"àáảãạăằắẳẵặâầấẩẫậ", "a"},
		{"ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ", "A"},
		{"èéẻẽẹêềếểễệ", "e"},
		{"ÈÉẺẼẸÊỀẾỂỄỆ", "E"},
		{"ìíỉĩị", "i"},
		{"ÌÍỈĨỊ", "I"},
		{"òóỏõọôồốổỗộơờớởỡợ", "o"},
		{"ÒÕỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ", "O"},
		{"ùúủũụưừứửữự", "u"},
		{"ÙÚỦŨỤƯỪỨỬỮỰ", "U"},
		{"ỳýỷỹỵ", "y"},
		{"ỲÝỶỸỴ", "Y"},
		{"đ", "d"},
		{"Đ", "D"},
	}

	for _, rep := range replacements {
		for _, char := range strings.Split(rep.from, "") {
			coverted = strings.ReplaceAll(coverted, char, rep.to)
		}
	}
	return coverted
}

// ensureFontsExist downloads Roboto Regular and Bold from Google Fonts if they do not exist locally.
func ensureFontsExist() error {
	fontDir := "fonts"
	regularPath := "fonts/Roboto-Regular.ttf"
	boldPath := "fonts/Roboto-Bold.ttf"

	if info, err := os.Stat(regularPath); err == nil && info.Size() > 10000 {
		if infoBold, errBold := os.Stat(boldPath); errBold == nil && infoBold.Size() > 10000 {
			return nil // Both exist and are valid size
		}
	}

	_ = os.MkdirAll(fontDir, 0755)

	// Fetch Roboto Regular
	if info, err := os.Stat(regularPath); err != nil || info.Size() <= 10000 {
		resp, err := http.Get("https://fastly.jsdelivr.net/gh/googlefonts/roboto-2@main/src/hinted/Roboto-Regular.ttf")
		if err != nil {
			return fmt.Errorf("failed to fetch regular font: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("failed to fetch regular font, status: %d", resp.StatusCode)
		}
		out, err := os.Create(regularPath)
		if err != nil {
			return err
		}
		defer out.Close()
		_, _ = io.Copy(out, resp.Body)
	}

	// Fetch Roboto Bold
	if info, err := os.Stat(boldPath); err != nil || info.Size() <= 10000 {
		resp, err := http.Get("https://fastly.jsdelivr.net/gh/googlefonts/roboto-2@main/src/hinted/Roboto-Bold.ttf")
		if err != nil {
			return fmt.Errorf("failed to fetch bold font: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return fmt.Errorf("failed to fetch bold font, status: %d", resp.StatusCode)
		}
		out, err := os.Create(boldPath)
		if err != nil {
			return err
		}
		defer out.Close()
		_, _ = io.Copy(out, resp.Body)
	}

	return nil
}

// Format currency in VND (e.g. 1.500.000)
func formatVND(amount int) string {
	str := fmt.Sprintf("%d", amount)
	var parts []string
	for len(str) > 3 {
		parts = append([]string{str[len(str)-3:]}, parts...)
		str = str[:len(str)-3]
	}
	if len(str) > 0 {
		parts = append([]string{str}, parts...)
	}
	return strings.Join(parts, ".")
}

// GeneratePriceListPDF builds a highly styled UTF-8 PDF document of the price list.
func GeneratePriceListPDF(pl map[string]interface{}) ([]byte, error) {
	if err := ensureFontsExist(); err != nil {
		return nil, fmt.Errorf("failed to download or load Vietnamese fonts: %w", err)
	}

	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.SetMargins(15, 15, 15)

	// Register UTF-8 Roboto fonts
	pdf.AddUTF8Font("Roboto", "", "fonts/Roboto-Regular.ttf")
	pdf.AddUTF8Font("Roboto", "B", "fonts/Roboto-Bold.ttf")

	pdf.AddPage()

	// Title Banner
	pdf.SetFillColor(230, 240, 255)
	pdf.Rect(15, 15, 180, 25, "F")

	pdf.SetFont("Roboto", "B", 18)
	pdf.SetTextColor(20, 80, 160)
	pdf.CellFormat(180, 25, "BẢNG BÁO GIÁ SẢN PHẨM", "", 0, "C", false, 0, "")
	pdf.Ln(30)

	// General Information Section
	description := getStringValue(pl["description"])
	buyerName := "Khách lẻ"
	if nameVal := getStringValue(pl["buyerName"]); nameVal != "" {
		buyerName = nameVal
	}

	phone := "N/A"
	if phoneVal := getStringValue(pl["phoneNumber"]); phoneVal != "" {
		phone = phoneVal
	}
	address := "N/A"
	if addrVal := getStringValue(pl["address"]); addrVal != "" {
		address = addrVal
	}

	pdf.SetTextColor(50, 50, 50)

	// Details layout
	pdf.SetFont("Roboto", "B", 10)
	pdf.CellFormat(35, 6, "Tên báo giá:", "", 0, "L", false, 0, "")
	pdf.SetFont("Roboto", "", 10)
	pdf.CellFormat(145, 6, description, "", 0, "L", false, 0, "")
	pdf.Ln(7)

	pdf.SetFont("Roboto", "B", 10)
	pdf.CellFormat(35, 6, "Khách hàng:", "", 0, "L", false, 0, "")
	pdf.SetFont("Roboto", "", 10)
	pdf.CellFormat(145, 6, buyerName, "", 0, "L", false, 0, "")
	pdf.Ln(7)

	pdf.SetFont("Roboto", "B", 10)
	pdf.CellFormat(35, 6, "Điện thoại:", "", 0, "L", false, 0, "")
	pdf.SetFont("Roboto", "", 10)
	pdf.CellFormat(145, 6, phone, "", 0, "L", false, 0, "")
	pdf.Ln(7)

	pdf.SetFont("Roboto", "B", 10)
	pdf.CellFormat(35, 6, "Địa chỉ:", "", 0, "L", false, 0, "")
	pdf.SetFont("Roboto", "", 10)
	pdf.CellFormat(145, 6, address, "", 0, "L", false, 0, "")
	pdf.Ln(7)

	pdf.SetFont("Roboto", "B", 10)
	pdf.CellFormat(35, 6, "Ngày xuất:", "", 0, "L", false, 0, "")
	pdf.SetFont("Roboto", "", 10)
	pdf.CellFormat(145, 6, time.Now().Format("02/01/2006 15:04"), "", 0, "L", false, 0, "")
	pdf.Ln(12)

	// Items Table Header
	pdf.SetFillColor(30, 100, 200)
	pdf.SetTextColor(255, 255, 255)
	pdf.SetFont("Roboto", "B", 10)

	pdf.CellFormat(15, 8, "STT", "1", 0, "C", true, 0, "")
	pdf.CellFormat(95, 8, "Tên mặt hàng", "1", 0, "L", true, 0, "")
	pdf.CellFormat(30, 8, "Đơn vị", "1", 0, "C", true, 0, "")
	pdf.CellFormat(40, 8, "Đơn giá (VND)", "1", 0, "C", true, 0, "")
	pdf.Ln(8)

	// Items Table Body
	pdf.SetTextColor(50, 50, 50)
	pdf.SetFont("Roboto", "", 9)

	items, ok := pl["itemPrices"].([]interface{})
	if ok && len(items) > 0 {
		for i, rawItm := range items {
			itm, ok := rawItm.(map[string]interface{})
			if !ok {
				continue
			}

			itemName := "Mặt hàng không tên"
			if itm["itemDefaultName"] != nil {
				itemName = fmt.Sprintf("%v", itm["itemDefaultName"])
			}
			unitName := "Cái"
			if itm["unitName"] != nil {
				unitName = fmt.Sprintf("%v", itm["unitName"])
			}
			price := 0
			if p, ok := itm["unitPriceCustom"].(float64); ok {
				price = int(p)
			} else if p, ok := itm["unitPriceCustom"].(int); ok {
				price = p
			}

			// Compute dynamic wrapped height for the row based on text length
			lines := pdf.SplitLines([]byte(itemName), 95)
			lineHeight := 5.0
			if len(lines) == 1 {
				lineHeight = 8.0
			}
			rowHeight := float64(len(lines)) * lineHeight

			// Check if we need to start a new page to prevent awkward page splits
			if pdf.GetY()+rowHeight > 275 {
				pdf.AddPage()

				// Redraw table headers on the new page
				pdf.SetFillColor(30, 100, 200)
				pdf.SetTextColor(255, 255, 255)
				pdf.SetFont("Roboto", "B", 10)

				pdf.CellFormat(15, 8, "STT", "1", 0, "C", true, 0, "")
				pdf.CellFormat(95, 8, "Tên mặt hàng", "1", 0, "L", true, 0, "")
				pdf.CellFormat(30, 8, "Đơn vị", "1", 0, "C", true, 0, "")
				pdf.CellFormat(40, 8, "Đơn giá (VND)", "1", 0, "C", true, 0, "")
				pdf.Ln(8)

				// Restore body text color and font
				pdf.SetTextColor(50, 50, 50)
				pdf.SetFont("Roboto", "", 9)
			}

			// Get current position (must be after page break check as AddPage updates Y)
			x := pdf.GetX()
			y := pdf.GetY()

			// Zebra shading
			if i%2 == 1 {
				pdf.SetFillColor(245, 248, 255)
			} else {
				pdf.SetFillColor(255, 255, 255)
			}

			// 1. STT
			pdf.CellFormat(15, rowHeight, fmt.Sprintf("%d", i+1), "1", 0, "C", true, 0, "")

			// 2. Item Name (wrapping)
			pdf.SetXY(x+15, y)
			pdf.MultiCell(95, lineHeight, itemName, "1", "L", true)

			// 3. Unit Name
			pdf.SetXY(x+15+95, y)
			pdf.CellFormat(30, rowHeight, unitName, "1", 0, "C", true, 0, "")

			// 4. Price
			pdf.CellFormat(40, rowHeight, formatVND(price), "1", 0, "C", true, 0, "")

			// Move to the next row starting position
			pdf.SetXY(x, y+rowHeight)
		}
	} else {
		pdf.CellFormat(180, 8, "Không có mặt hàng nào trong báo giá", "1", 0, "C", false, 0, "")
		pdf.Ln(8)
	}

	// Check if there is enough space for footnotes on the current page to prevent awkward page end splits
	if pdf.GetY() > 255 {
		pdf.AddPage()
	}
	pdf.Ln(10)

	// Note Footer
	pdf.SetFont("Roboto", "B", 9)
	pdf.SetTextColor(120, 120, 120)
	pdf.CellFormat(180, 6, "* Báo giá trên đã bao gồm các khoản thuế phí liên quan.", "", 0, "L", false, 0, "")
	pdf.Ln(6)
	pdf.CellFormat(180, 6, "* Xin chân thành cảm ơn Sự tin tưởng hợp tác của Quý khách hàng!", "", 0, "L", false, 0, "")

	var buf bytes.Buffer
	err := pdf.Output(&buf)
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// GeneratePriceListExcel generates a standard Excel spreadsheet using excelize.
func GeneratePriceListExcel(pl map[string]interface{}) ([]byte, error) {
	f := excelize.NewFile()
	defer f.Close()

	sheetName := "Báo giá"
	f.SetSheetName("Sheet1", sheetName)

	// 1. Title Row
	f.SetCellValue(sheetName, "A1", "BẢNG BÁO GIÁ SẢN PHẨM")
	f.MergeCell(sheetName, "A1", "D1")

	titleStyle, err := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Bold:  true,
			Size:  16,
			Color: "1E64C8",
		},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Color:   []string{"E6F0FF"},
			Pattern: 1,
		},
	})
	if err == nil {
		f.SetCellStyle(sheetName, "A1", "D1", titleStyle)
		f.SetRowHeight(sheetName, 1, 35)
	}

	// 2. Info Block
	description := getStringValue(pl["description"])
	buyerName := "Khách lẻ"
	if nameVal := getStringValue(pl["buyerName"]); nameVal != "" {
		buyerName = nameVal
	}

	phone := "N/A"
	if phoneVal := getStringValue(pl["phoneNumber"]); phoneVal != "" {
		phone = phoneVal
	}
	address := "N/A"
	if addrVal := getStringValue(pl["address"]); addrVal != "" {
		address = addrVal
	}

	f.SetCellValue(sheetName, "A3", "Tên báo giá:")
	f.SetCellValue(sheetName, "B3", description)
	f.MergeCell(sheetName, "B3", "D3")

	f.SetCellValue(sheetName, "A4", "Khách hàng:")
	f.SetCellValue(sheetName, "B4", buyerName)
	f.MergeCell(sheetName, "B4", "D4")

	f.SetCellValue(sheetName, "A5", "Số điện thoại:")
	f.SetCellValue(sheetName, "B5", phone)
	f.MergeCell(sheetName, "B5", "D5")

	f.SetCellValue(sheetName, "A6", "Địa chỉ:")
	f.SetCellValue(sheetName, "B6", address)
	f.MergeCell(sheetName, "B6", "D6")

	f.SetCellValue(sheetName, "A7", "Ngày xuất:")
	f.SetCellValue(sheetName, "B7", time.Now().Format("02/01/2006 15:04"))
	f.MergeCell(sheetName, "B7", "D7")

	labelStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true},
	})
	f.SetCellStyle(sheetName, "A3", "A7", labelStyle)

	// 3. Table Headers
	headers := []string{"STT", "Tên mặt hàng", "Đơn vị tính", "Đơn giá (VND)"}
	for colIndex, header := range headers {
		cellName, _ := excelize.CoordinatesToCellName(colIndex+1, 9)
		f.SetCellValue(sheetName, cellName, header)
	}

	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Bold:  true,
			Color: "FFFFFF",
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Color:   []string{"1E64C8"},
			Pattern: 1,
		},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
		},
		Border: []excelize.Border{
			{Type: "top", Color: "000000", Style: 1},
			{Type: "bottom", Color: "000000", Style: 1},
			{Type: "left", Color: "000000", Style: 1},
			{Type: "right", Color: "000000", Style: 1},
		},
	})
	f.SetCellStyle(sheetName, "A9", "D9", headerStyle)
	f.SetRowHeight(sheetName, 9, 24)

	// 4. Item Rows
	rowStyleLeft, _ := f.NewStyle(&excelize.Style{
		Alignment: &excelize.Alignment{Horizontal: "left", Vertical: "center", WrapText: true},
		Border: []excelize.Border{
			{Type: "top", Color: "CCCCCC", Style: 1},
			{Type: "bottom", Color: "CCCCCC", Style: 1},
			{Type: "left", Color: "CCCCCC", Style: 1},
			{Type: "right", Color: "CCCCCC", Style: 1},
		},
	})

	rowStyleCenter, _ := f.NewStyle(&excelize.Style{
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
		Border: []excelize.Border{
			{Type: "top", Color: "CCCCCC", Style: 1},
			{Type: "bottom", Color: "CCCCCC", Style: 1},
			{Type: "left", Color: "CCCCCC", Style: 1},
			{Type: "right", Color: "CCCCCC", Style: 1},
		},
	})

	priceStyleCenter, _ := f.NewStyle(&excelize.Style{
		NumFmt:    3, // #,##0 decimal pattern format
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
		Border: []excelize.Border{
			{Type: "top", Color: "CCCCCC", Style: 1},
			{Type: "bottom", Color: "CCCCCC", Style: 1},
			{Type: "left", Color: "CCCCCC", Style: 1},
			{Type: "right", Color: "CCCCCC", Style: 1},
		},
	})

	items, ok := pl["itemPrices"].([]interface{})
	currentRow := 10
	if ok && len(items) > 0 {
		for i, rawItm := range items {
			itm, ok := rawItm.(map[string]interface{})
			if !ok {
				continue
			}

			itemName := "Mặt hàng không tên"
			if itm["itemDefaultName"] != nil {
				itemName = fmt.Sprintf("%v", itm["itemDefaultName"])
			}
			unitName := "Cái"
			if itm["unitName"] != nil {
				unitName = fmt.Sprintf("%v", itm["unitName"])
			}
			price := 0
			if p, ok := itm["unitPriceCustom"].(float64); ok {
				price = int(p)
			} else if p, ok := itm["unitPriceCustom"].(int); ok {
				price = p
			}

			f.SetCellValue(sheetName, fmt.Sprintf("A%d", currentRow), i+1)
			f.SetCellValue(sheetName, fmt.Sprintf("B%d", currentRow), itemName)
			f.SetCellValue(sheetName, fmt.Sprintf("C%d", currentRow), unitName)
			f.SetCellValue(sheetName, fmt.Sprintf("D%d", currentRow), price)

			f.SetCellStyle(sheetName, fmt.Sprintf("A%d", currentRow), fmt.Sprintf("A%d", currentRow), rowStyleCenter)
			f.SetCellStyle(sheetName, fmt.Sprintf("B%d", currentRow), fmt.Sprintf("B%d", currentRow), rowStyleLeft)
			f.SetCellStyle(sheetName, fmt.Sprintf("C%d", currentRow), fmt.Sprintf("C%d", currentRow), rowStyleCenter)
			f.SetCellStyle(sheetName, fmt.Sprintf("D%d", currentRow), fmt.Sprintf("D%d", currentRow), priceStyleCenter)

			// We do not explicitly set a fixed row height here so that Excel's dynamic layout engine
			// can auto-adjust row heights to perfectly fit wrapped multi-line item names!
			currentRow++
		}
	} else {
		f.SetCellValue(sheetName, "A10", "Không có mặt hàng nào")
		f.MergeCell(sheetName, "A10", "D10")
		f.SetCellStyle(sheetName, "A10", "D10", rowStyleLeft)
		currentRow++
	}

	// 5. Footnotes
	currentRow += 2
	f.SetCellValue(sheetName, fmt.Sprintf("A%d", currentRow), "* Báo giá trên đã bao gồm thuế phí liên quan.")
	f.SetCellValue(sheetName, fmt.Sprintf("A%d", currentRow+1), "* Xin chân thành cảm ơn Sự tin tưởng hợp tác của Quý khách hàng!")

	footnoteStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Italic: true, Size: 9, Color: "777777"},
	})
	f.SetCellStyle(sheetName, fmt.Sprintf("A%d", currentRow), fmt.Sprintf("A%d", currentRow+1), footnoteStyle)

	// Auto-fit Columns (Column A has a fixed width to fit label fields above, others are auto-fitted)
	cols, err := f.GetCols(sheetName)
	if err == nil {
		for colIdx, col := range cols {
			if colIdx == 0 {
				// STT Column is set to 16 so it perfectly fits the longest label field above ("Số điện thoại:" is 14 chars)
				f.SetColWidth(sheetName, "A", "A", 16)
				continue
			}
			maxLen := 0
			for _, val := range col {
				if len(val) > maxLen {
					maxLen = len(val)
				}
			}
			colName, _ := excelize.CoordinatesToCellName(colIdx+1, 1)
			colLetter := strings.TrimRight(colName, "1")
			width := float64(maxLen) + 3.0
			if width < 12 {
				width = 12
			}
			if width > 40 {
				width = 40
			}
			f.SetColWidth(sheetName, colLetter, colLetter, width)
		}
	}

	var buf bytes.Buffer
	err = f.Write(&buf)
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
