package invoice

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"

	"github.com/jung-kurt/gofpdf/v2"
	"github.com/skip2/go-qrcode"
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

// removeDiacritics converts accented Vietnamese characters to plain ASCII for safe metadata.
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

// splitAddressNumber splits a street address into the initial number part (e.g., "26", "26/4", "Số 26") and the remaining text.
func splitAddressNumber(addr string) (string, string) {
	addr = strings.TrimSpace(addr)
	if addr == "" {
		return "", ""
	}

	firstSpace := strings.Index(addr, " ")
	if firstSpace == -1 {
		if containsDigit(addr) {
			return addr, ""
		}
		return "", addr
	}

	firstWord := addr[:firstSpace]
	if containsDigit(firstWord) {
		return firstWord, addr[firstSpace+1:]
	}

	// Check if it starts with "Số" or similar
	if strings.ToLower(firstWord) == "số" {
		rest := addr[firstSpace+1:]
		secondSpace := strings.Index(rest, " ")
		if secondSpace != -1 {
			secondWord := rest[:secondSpace]
			if containsDigit(secondWord) {
				return firstWord + " " + secondWord, rest[secondSpace+1:]
			}
		} else {
			if containsDigit(rest) {
				return firstWord + " " + rest, ""
			}
		}
	}

	return "", addr
}

func containsDigit(s string) bool {
	for _, r := range s {
		if r >= '0' && r <= '9' {
			return true
		}
	}
	return false
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
func formatVND(amount int64) string {
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

// GenerateInvoicePDF builds a highly styled UTF-8 PDF document of the invoice on A5 paper.
func GenerateInvoicePDF(inv map[string]interface{}, printType string, printPart string) ([]byte, error) {
	if err := ensureFontsExist(); err != nil {
		return nil, fmt.Errorf("failed to download or load Vietnamese fonts: %w", err)
	}

	// Initialize A5 portrait document
	pdf := gofpdf.New("P", "mm", "A5", "")
	marginSide := 5.0
	printableWidth := 148.0 - (2 * marginSide)
	pdf.SetMargins(marginSide, 6, marginSide)
	pdf.SetAutoPageBreak(false, 0)

	// Generate QR Code containing ivid:{invoiceId}
	invoiceID := getStringValue(inv["invoiceId"])
	qrContent := fmt.Sprintf("ivid:%s", invoiceID)
	var qrPng []byte
	var qrErr error
	if invoiceID != "" {
		var qr *qrcode.QRCode
		qr, qrErr = qrcode.New(qrContent, qrcode.Medium)
		if qrErr == nil {
			qr.DisableBorder = true
			qrPng, qrErr = qr.PNG(256)
		}
		if qrErr == nil && len(qrPng) > 0 {
			imgReader := bytes.NewReader(qrPng)
			pdf.RegisterImageOptionsReader("invoice_qrcode", gofpdf.ImageOptions{ImageType: "PNG", ReadDpi: true}, imgReader)
		}
	}

	// Register UTF-8 Roboto fonts
	pdf.AddUTF8Font("Roboto", "", "fonts/Roboto-Regular.ttf")
	pdf.AddUTF8Font("Roboto", "B", "fonts/Roboto-Bold.ttf")

	// Determine copies
	var copies []string
	if printType == "Triplicate" {
		copies = []string{"Liên A", "Liên B", "Liên C"}
	} else {
		// printType == "Original"
		switch printPart {
		case "A":
			copies = []string{"Liên A"}
		case "B":
			copies = []string{"Liên B"}
		case "C":
			copies = []string{"Liên C"}
		default:
			copies = []string{""} // Default means no "Liên A/B/C" printed at all
		}
	}

	// Extract data
	invoiceCode := getStringValue(inv["invoiceCode"])
	if invoiceCode == "" {
		invoiceCode = getStringValue(inv["invoiceId"])
	}
	printJobID := getStringValue(inv["printJobId"])
	buyerName := "Khách vãng lai"
	if val := getStringValue(inv["buyerNameSnapshot"]); val != "" && val != "N/A" {
		buyerName = val
	}
	address := ""
	if val := getStringValue(inv["addressSnapshot"]); val != "" && val != "N/A" {
		address = val
	}
	phone := ""
	if val := getStringValue(inv["phoneNumberSnapshot"]); val != "" && val != "N/A" {
		phone = val
	}

	// Line items
	rawItems, _ := inv["lineItems"].([]interface{})
	var items []map[string]interface{}
	for _, rawItm := range rawItems {
		if itm, ok := rawItm.(map[string]interface{}); ok {
			items = append(items, itm)
		}
	}

	// Grand total amount
	var grandTotal int64
	if gt, ok := inv["totalAmount"].(float64); ok {
		grandTotal = int64(gt)
	} else if gt, ok := inv["totalAmount"].(int64); ok {
		grandTotal = gt
	} else if gt, ok := inv["totalAmount"].(int); ok {
		grandTotal = int64(gt)
	}

	// ----------------------------------------------------
	// CALCULATE DYNAMIC FLEXIBLE COLUMN WIDTHS
	// ----------------------------------------------------
	tableFontSize := 13.0 // 12pt is ~4.23mm, which is exactly ~45% of the 9.5mm row line height for a highly professional, high-end invoice layout
	wSTT := 9.0           // safe space for STT numbers

	pdf.SetFont("Roboto", "B", tableFontSize)
	wUnitMin := pdf.GetStringWidth("Đơn vị")
	wQtyMin := pdf.GetStringWidth("S.Lg")
	wUnitPriceMin := pdf.GetStringWidth("Đơn giá")
	wPriceMin := pdf.GetStringWidth("T.Tiền")

	pdf.SetFont("Roboto", "", tableFontSize)
	for _, itm := range items {
		// Unit Name
		unitName := getStringValue(itm["unitNameSnapshot"])
		wUn := pdf.GetStringWidth(unitName)
		if wUn > wUnitMin {
			wUnitMin = wUn
		}

		// Quantity
		var qty int32
		if q, ok := itm["quantity"].(float64); ok {
			qty = int32(q)
		} else if q, ok := itm["quantity"].(int32); ok {
			qty = q
		} else if q, ok := itm["quantity"].(int); ok {
			qty = int32(q)
		}
		wQt := pdf.GetStringWidth(fmt.Sprintf("%d", qty))
		if wQt > wQtyMin {
			wQtyMin = wQt
		}

		// Unit Price
		var price int64
		if p, ok := itm["unitPriceCustom"].(float64); ok {
			price = int64(p)
		} else if p, ok := itm["unitPriceCustom"].(int64); ok {
			price = p
		} else if p, ok := itm["unitPriceCustom"].(int); ok {
			price = int64(p)
		}

		wUp := pdf.GetStringWidth(formatVND(price))
		if wUp > wUnitPriceMin {
			wUnitPriceMin = wUp
		}

		// Subtotal (T.Tiền)
		var subTotal int64
		if s, ok := itm["subTotal"].(float64); ok {
			subTotal = int64(s)
		} else if s, ok := itm["subTotal"].(int64); ok {
			subTotal = s
		} else if s, ok := itm["subTotal"].(int); ok {
			subTotal = int64(s)
		}

		wSt := pdf.GetStringWidth(formatVND(subTotal))
		if wSt > wPriceMin {
			wPriceMin = wSt
		}
	}

	// Add 2.0mm of padding for safe spacing/borders (1.0mm on each side)
	wUnit := wUnitMin + 2.0
	wQty := wQtyMin + 2.0
	wUnitPrice := wUnitPriceMin + 2.0
	wPrice := wPriceMin + 2.0

	// wName takes the remaining horizontal space of printable area
	wName := printableWidth - (wSTT + wUnit + wQty + wUnitPrice + wPrice)
	if wName < 30.0 {
		wName = 30.0 // safety fallback
	}

	// DEBUG WRITE FILE
	var debugBuf bytes.Buffer
	debugBuf.WriteString(fmt.Sprintf("wName: %f, margin: %f, printableWidth: %f\n", wName, pdf.GetCellMargin(), printableWidth))
	pdf.SetFont("Roboto", "B", tableFontSize)
	for i, itm := range items {
		name := strings.TrimSpace(getStringValue(itm["itemNameSnapshot"]))
		lines := pdf.SplitText(name, wName)
		debugBuf.WriteString(fmt.Sprintf("Item %d: %q, len(lines): %d\n", i+1, name, len(lines)))
		for idx, l := range lines {
			debugBuf.WriteString(fmt.Sprintf("  Line %d: %q\n", idx+1, l))
		}
	}
	_ = os.WriteFile("debug_lines.txt", debugBuf.Bytes(), 0644)

	// ----------------------------------------------------
	// PROFESSIONAL PRE-CALCULATED PAGINATION WITH ROW MERGING
	// ----------------------------------------------------
	type RenderedRow struct {
		Item       map[string]interface{} // nil if empty padding row
		STT        int
		Slots      int // how many slots (lines) this row takes: 1, 2, 3, etc.
		ZebraIndex int
	}

	type RenderedPage struct {
		Rows      []RenderedRow
		PageTotal int64
	}

	var pages []RenderedPage

	currItemIdx := 0
	totalItems := len(items)
	zebraIdx := 0

	for currItemIdx < totalItems {
		var pageRows []RenderedRow
		var pageTotal int64
		slotsUsed := 0

		for currItemIdx < totalItems {
			itm := items[currItemIdx]
			itemName := strings.TrimSpace(getStringValue(itm["itemNameSnapshot"]))

			// Calculate slots needed based on Roboto font wrapping using UTF-8 safe SplitText
			pdf.SetFont("Roboto", "B", tableFontSize)
			lines := pdf.SplitText(itemName, wName)
			slotsNeeded := len(lines)
			if slotsNeeded < 1 {
				slotsNeeded = 1
			}
			if slotsNeeded > 15 {
				slotsNeeded = 15 // Cap at max page slots as fail-safe
			}

			if slotsUsed+slotsNeeded > 15 {
				// Cannot fit on this page, push to next page
				break
			}

			var subTotal int64
			if s, ok := itm["subTotal"].(float64); ok {
				subTotal = int64(s)
			} else if s, ok := itm["subTotal"].(int64); ok {
				subTotal = s
			} else if s, ok := itm["subTotal"].(int); ok {
				subTotal = int64(s)
			}

			pageTotal += subTotal

			pageRows = append(pageRows, RenderedRow{
				Item:       itm,
				STT:        currItemIdx + 1,
				Slots:      slotsNeeded,
				ZebraIndex: zebraIdx,
			})

			slotsUsed += slotsNeeded
			zebraIdx++
			currItemIdx++
		}

		// Pad with empty rows to make exactly 15 slots
		if slotsUsed < 15 {
			emptySlotsNeeded := 15 - slotsUsed
			for i := 0; i < emptySlotsNeeded; i++ {
				pageRows = append(pageRows, RenderedRow{
					Item:       nil,
					STT:        0,
					Slots:      1,
					ZebraIndex: zebraIdx,
				})
				zebraIdx++
			}
		}

		pages = append(pages, RenderedPage{
			Rows:      pageRows,
			PageTotal: pageTotal,
		})
	}

	if len(pages) == 0 {
		// Empty Invoice fallback
		var pageRows []RenderedRow
		for i := 0; i < 15; i++ {
			pageRows = append(pageRows, RenderedRow{
				Item:       nil,
				STT:        0,
				Slots:      1,
				ZebraIndex: i,
			})
		}
		pages = append(pages, RenderedPage{
			Rows:      pageRows,
			PageTotal: 0,
		})
	}

	totalPages := len(pages)

	// ----------------------------------------------------
	// GENERATE PAGES FOR EACH COPY
	// ----------------------------------------------------
	for _, copyName := range copies {
		for pageIdx, pData := range pages {
			pdf.AddPage()
			pdf.SetDrawColor(0, 0, 0)

			// Draw header
			pdf.SetTextColor(20, 80, 160)
			pdf.SetFont("Roboto", "B", 16)
			pdf.CellFormat(printableWidth, 5, "HOÁ ĐƠN", "", 0, "C", false, 0, "")
			pdf.Ln(6)

			// Customer info section (Left Side) & QR Box (Right Side)
			pdf.SetTextColor(50, 50, 50)

			startX := pdf.GetX()
			startY := pdf.GetY()

			// Left Side Customer Details
			pdf.SetXY(startX, startY)

			// 1. Tên khách hàng (Use MultiCell to wrap beautifully if too long without overflowing QR box)
			if buyerName != "" {
				pdf.SetFont("Roboto", "B", 11)
				pdf.CellFormat(30, 4.5, "Tên khách hàng:", "", 0, "L", false, 0, "")
				pdf.SetFont("Roboto", "", 11)
				pdf.MultiCell(90, 4.5, buyerName, "", "L", false)
			}

			// 2. Địa chỉ (MultiCell)
			if address != "" {
				pdf.SetFont("Roboto", "B", 11)
				pdf.CellFormat(30, 4.5, "Địa chỉ:", "", 0, "L", false, 0, "")
				
				numPart, restPart := splitAddressNumber(address)
				if numPart != "" {
					pdf.SetFont("Roboto", "B", 11)
					wNum := pdf.GetStringWidth(numPart + " ")
					
					pdf.SetFont("Roboto", "", 11)
					firstLineSplit := pdf.SplitText(restPart, 90-wNum)
					
					if len(firstLineSplit) > 0 {
						pdf.SetFont("Roboto", "B", 11)
						pdf.CellFormat(wNum, 4.5, numPart+" ", "", 0, "L", false, 0, "")
						
						pdf.SetFont("Roboto", "", 11)
						firstLineText := firstLineSplit[0]
						
						if len(firstLineSplit) > 1 {
							// Print first line text, then carriage return
							pdf.CellFormat(90-wNum, 4.5, firstLineText, "", 1, "L", false, 0, "")
							
							// Extract remainder of address to wrap under the same margin
							remainder := ""
							if strings.HasPrefix(restPart, firstLineText) {
								remainder = strings.TrimSpace(restPart[len(firstLineText):])
							} else {
								remainder = strings.Join(firstLineSplit[1:], " ")
							}
							
							if remainder != "" {
								// Set X back to the same column margin as "123 Trường" (which is startX + 30)
								pdf.SetX(startX + 30)
								pdf.MultiCell(90, 4.5, remainder, "", "L", false)
							}
						} else {
							// Everything fits in the first line, just print it and move to next line
							pdf.MultiCell(90-wNum, 4.5, firstLineText, "", "L", false)
						}
					} else {
						// Fallback if split text is empty (should not happen)
						pdf.SetFont("Roboto", "B", 11)
						pdf.CellFormat(wNum, 4.5, numPart+" ", "", 0, "L", false, 0, "")
						pdf.Ln(4.5)
					}
				} else {
					pdf.SetFont("Roboto", "", 11)
					pdf.MultiCell(90, 4.5, address, "", "L", false)
				}
			}

			// 3. Số điện thoại (MultiCell)
			if phone != "" {
				pdf.SetFont("Roboto", "B", 11)
				pdf.CellFormat(30, 4.5, "Số điện thoại:", "", 0, "L", false, 0, "")
				pdf.SetFont("Roboto", "", 11)
				pdf.MultiCell(90, 4.5, phone, "", "L", false)
			}

			customerEndY := pdf.GetY()

			// Right Side: QR Code Box (positioned at startY)
			qrBoxSize := 20.0
			qrX := startX + printableWidth - qrBoxSize
			qrY := startY

			if qrErr == nil && len(qrPng) > 0 {
				pdf.ImageOptions("invoice_qrcode", qrX, qrY, qrBoxSize, qrBoxSize, false, gofpdf.ImageOptions{ImageType: "PNG", ReadDpi: true}, 0, "")
			} else {
				// Fallback to empty QR box with border if QR generation failed or missing
				pdf.SetDrawColor(120, 120, 120)
				pdf.SetLineWidth(0.3)
				pdf.Rect(qrX, qrY, qrBoxSize, qrBoxSize, "D")
			}

			// Calculate dynamic table starting Y position
			tableStartY := customerEndY
			qrEndY := qrY + qrBoxSize
			if qrEndY > tableStartY {
				tableStartY = qrEndY
			}
			tableStartY += 2.0 // Add a clean 2mm space before starting the table

			// Set the cursor to tableStartY for drawing the table header
			pdf.SetXY(startX, tableStartY)

			// Table Header
			pdf.SetFillColor(30, 100, 200)
			pdf.SetTextColor(255, 255, 255)
			pdf.SetFont("Roboto", "B", tableFontSize)
			pdf.SetLineWidth(0.35)

			pdf.CellFormat(wSTT, 8.5, "STT", "1", 0, "C", true, 0, "")
			pdf.CellFormat(wName, 8.5, "Tên hàng", "1", 0, "L", true, 0, "")
			pdf.CellFormat(wUnit, 8.5, "Đơn vị", "1", 0, "C", true, 0, "")
			pdf.CellFormat(wQty, 8.5, "S.Lg", "1", 0, "C", true, 0, "")
			pdf.CellFormat(wUnitPrice, 8.5, "Đơn giá", "1", 0, "C", true, 0, "")
			pdf.CellFormat(wPrice, 8.5, "T.Tiền", "1", 0, "C", true, 0, "")
			pdf.Ln(8.5)

			// Reset body fonts and colors
			pdf.SetTextColor(50, 50, 50)

			// Draw pre-calculated page rows
			for _, row := range pData.Rows {
				if row.ZebraIndex%2 == 1 {
					pdf.SetFillColor(245, 248, 255)
				} else {
					pdf.SetFillColor(255, 255, 255)
				}

				rowHeight := float64(row.Slots) * 8.5

				if row.Item != nil {
					// Actual Item Row
					itemName := strings.TrimSpace(getStringValue(row.Item["itemNameSnapshot"]))
					unitName := getStringValue(row.Item["unitNameSnapshot"])

					var qty int32
					if q, ok := row.Item["quantity"].(float64); ok {
						qty = int32(q)
					} else if q, ok := row.Item["quantity"].(int32); ok {
						qty = q
					} else if q, ok := row.Item["quantity"].(int); ok {
						qty = int32(q)
					}

					var price int64
					if p, ok := row.Item["unitPriceCustom"].(float64); ok {
						price = int64(p)
					} else if p, ok := row.Item["unitPriceCustom"].(int64); ok {
						price = p
					} else if p, ok := row.Item["unitPriceCustom"].(int); ok {
						price = int64(p)
					}

					var subTotal int64
					if s, ok := row.Item["subTotal"].(float64); ok {
						subTotal = int64(s)
					} else if s, ok := row.Item["subTotal"].(int64); ok {
						subTotal = s
					} else if s, ok := row.Item["subTotal"].(int); ok {
						subTotal = int64(s)
					}

					x := pdf.GetX()
					y := pdf.GetY()

					// 1. STT (Regular)
					pdf.SetFont("Roboto", "", tableFontSize)
					pdf.CellFormat(wSTT, rowHeight, fmt.Sprintf("%d", row.STT), "1", 0, "C", true, 0, "")

					// 2. Item Name (Bold)
					pdf.SetFont("Roboto", "B", tableFontSize)
					lines := pdf.SplitText(itemName, wName)
					numLines := len(lines)
					if numLines < 1 {
						numLines = 1
					}

					// 13.0pt font size is ~4.58mm. A line height of 6.0mm keeps lines beautifully close and readable.
					lineSpacing := 6.0
					actualTextHeight := float64(numLines) * lineSpacing
					verticalOffset := (rowHeight - actualTextHeight) / 2.0
					if verticalOffset < 0.2 {
						verticalOffset = 0.2
					}

					// Draw the outer table cell box first (handles borders and zebra fill)
					pdf.SetXY(x+wSTT, y)
					pdf.CellFormat(wName, rowHeight, "", "1", 0, "L", true, 0, "")

					// Draw the wrapped text centered vertically inside the cell without extra borders or fill
					pdf.SetXY(x+wSTT, y+verticalOffset)
					pdf.MultiCell(wName, lineSpacing, itemName, "", "L", false)

					// 3. Unit (Regular)
					pdf.SetFont("Roboto", "", tableFontSize)
					pdf.SetXY(x+wSTT+wName, y)
					pdf.CellFormat(wUnit, rowHeight, unitName, "1", 0, "C", true, 0, "")

					// 4. Quantity (Bold)
					pdf.SetFont("Roboto", "B", tableFontSize)
					pdf.CellFormat(wQty, rowHeight, fmt.Sprintf("%d", qty), "1", 0, "C", true, 0, "")

					// 5. Unit Price (Regular)
					pdf.SetFont("Roboto", "", tableFontSize)
					pdf.CellFormat(wUnitPrice, rowHeight, formatVND(price), "1", 0, "C", true, 0, "")

					// 6. Subtotal (T.Tiền) (Regular)
					pdf.CellFormat(wPrice, rowHeight, formatVND(subTotal), "1", 0, "C", true, 0, "")

					pdf.SetXY(x, y+rowHeight)
				} else {
					// Empty Row Padding
					pdf.SetFont("Roboto", "", tableFontSize)
					pdf.CellFormat(wSTT, rowHeight, "", "1", 0, "C", true, 0, "")
					pdf.CellFormat(wName, rowHeight, "", "1", 0, "L", true, 0, "")
					pdf.CellFormat(wUnit, rowHeight, "", "1", 0, "C", true, 0, "")
					pdf.CellFormat(wQty, rowHeight, "", "1", 0, "C", true, 0, "")
					pdf.CellFormat(wUnitPrice, rowHeight, "", "1", 0, "C", true, 0, "")
					pdf.CellFormat(wPrice, rowHeight, "", "1", 0, "C", true, 0, "")
					pdf.Ln(rowHeight)
				}
			}

			// Footer section
			pdf.Ln(1.5)

			if totalPages > 1 {
				pdf.SetFont("Roboto", "B", 14)
				pdf.CellFormat(printableWidth-60.0, 5.5, "Tổng tiền/tờ:", "", 0, "R", false, 0, "")
				pdf.CellFormat(60.0, 5.5, formatVND(pData.PageTotal)+" VND", "", 0, "R", false, 0, "")
				pdf.Ln(7.5)
			}

			pdf.SetFont("Roboto", "B", 17)
			pdf.CellFormat(printableWidth-60.0, 6.5, "Tổng tiền hoá đơn:", "", 0, "R", false, 0, "")
			pdf.CellFormat(60.0, 6.5, formatVND(grandTotal)+" VND", "", 0, "R", false, 0, "")

			// Absolute bottom constraints for line divider, Invoice ID, and copy info
			pdf.SetDrawColor(0, 0, 0)
			pdf.SetLineWidth(0.45)
			pdf.Line(marginSide, 198.0, marginSide+printableWidth, 198.0)

			pdf.SetXY(marginSide, 200.0)
			pdf.SetTextColor(0, 0, 0)

			// Middle side (optional): Print Job ID (clean 8.5pt font, centered)
			if printJobID != "" {
				pdf.SetFont("Roboto", "", 8.5)
				pdf.CellFormat(printableWidth, 4.0, "Job: "+printJobID, "", 0, "C", false, 0, "")
				pdf.SetXY(marginSide, 200.0) // Reset cursor for left/right cells
			}

			// Left side: Invoice ID (clean 8.5pt font)
			pdf.SetFont("Roboto", "", 8.5)
			pdf.CellFormat(printableWidth/2, 4.0, "ID: "+invoiceCode, "", 0, "L", false, 0, "")

			// Right side: Copy & Page Index (bold 9.0pt font)
			pdf.SetFont("Roboto", "B", 9.0)
			var footerText string
			if copyName != "" {
				footerText = fmt.Sprintf("%s - %d/%d", copyName, pageIdx+1, totalPages)
			} else {
				footerText = fmt.Sprintf("%d/%d", pageIdx+1, totalPages)
			}
			pdf.CellFormat(printableWidth/2, 4.0, footerText, "", 0, "R", false, 0, "")
		}
	}

	var buf bytes.Buffer
	err := pdf.Output(&buf)
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
