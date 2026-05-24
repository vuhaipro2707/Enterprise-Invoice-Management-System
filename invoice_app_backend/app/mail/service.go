package mail

import (
	"encoding/base64"
	"fmt"
	"net/smtp"
	"os"
)

// SendEmailWithAttachment creates and sends a multipart MIME email with attachment over Gmail SMTP.
func SendEmailWithAttachment(recipient, subject, bodyHTML, attachmentName string, attachmentBytes []byte) error {
	mailUser := os.Getenv("MAIL_USER")
	mailPassword := os.Getenv("MAIL_PASSWORD")
	if mailUser == "" || mailPassword == "" {
		return fmt.Errorf("email sender credentials not configured in environment (MAIL_USER, MAIL_PASSWORD)")
	}

	smtpHost := "smtp.gmail.com"
	smtpPort := "587"
	auth := smtp.PlainAuth("", mailUser, mailPassword, smtpHost)

	// Unique boundary token
	boundary := "==Multipart_Email_Boundary_XYZ_123=="

	// Compile Email Headers
	msg := fmt.Sprintf("From: %s\r\n", mailUser)
	msg += fmt.Sprintf("To: %s\r\n", recipient)
	msg += fmt.Sprintf("Subject: %s\r\n", subject)
	msg += "MIME-Version: 1.0\r\n"
	msg += fmt.Sprintf("Content-Type: multipart/mixed; boundary=\"%s\"\r\n", boundary)
	msg += "\r\n"

	// 1. Text/HTML Body section
	msg += fmt.Sprintf("--%s\r\n", boundary)
	msg += "Content-Type: text/html; charset=\"UTF-8\"\r\n"
	msg += "Content-Transfer-Encoding: 7bit\r\n"
	msg += "\r\n"
	msg += bodyHTML
	msg += "\r\n\r\n"

	// 2. Attachment section
	if len(attachmentBytes) > 0 {
		msg += fmt.Sprintf("--%s\r\n", boundary)
		msg += fmt.Sprintf("Content-Type: application/octet-stream; name=\"%s\"\r\n", attachmentName)
		msg += "Content-Transfer-Encoding: base64\r\n"
		msg += fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n", attachmentName)
		msg += "\r\n"

		// Base64 encode and split chunks at 76 characters for SMTP standard compatibility
		encoded := base64.StdEncoding.EncodeToString(attachmentBytes)
		for i := 0; i < len(encoded); i += 76 {
			end := i + 76
			if end > len(encoded) {
				end = len(encoded)
			}
			msg += encoded[i:end] + "\r\n"
		}
		msg += "\r\n"
	}

	// Final boundary close tag
	msg += fmt.Sprintf("--%s--\r\n", boundary)

	// Send message using TLS/STARTTLS on Gmail port 587
	err := smtp.SendMail(smtpHost+":"+smtpPort, auth, mailUser, []string{recipient}, []byte(msg))
	if err != nil {
		return fmt.Errorf("SMTP sending failure: %w", err)
	}

	return nil
}
