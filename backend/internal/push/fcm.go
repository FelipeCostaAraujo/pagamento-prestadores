// Package push sends notifications through Firebase Cloud Messaging.
package push

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// scope is the only permission the service account needs.
const scope = "https://www.googleapis.com/auth/firebase.messaging"

// ErrDisabled is returned by New when no credential is configured. It is not a
// failure: an install without push still works, it just does not remind.
var ErrDisabled = errors.New("push disabled: no service account configured")

// Sender delivers messages to device tokens.
type Sender struct {
	projectID string
	client    *http.Client
}

// New builds a sender from a Google service-account JSON file.
//
// The file is the credential that authorises sending on behalf of the Firebase
// project, so it belongs on the server and nowhere near the app.
func New(ctx context.Context, credentialsPath string) (*Sender, error) {
	if strings.TrimSpace(credentialsPath) == "" {
		return nil, ErrDisabled
	}

	raw, err := os.ReadFile(credentialsPath)
	if err != nil {
		return nil, fmt.Errorf("read service account: %w", err)
	}

	// The project id is inside the credential, so there is nothing extra to
	// configure and nothing that can drift out of sync with it.
	var meta struct {
		ProjectID string `json:"project_id"`
		Type      string `json:"type"`
	}
	if err := json.Unmarshal(raw, &meta); err != nil {
		return nil, fmt.Errorf("parse service account: %w", err)
	}
	if meta.ProjectID == "" {
		return nil, errors.New("service account has no project_id")
	}
	if meta.Type != "service_account" {
		return nil, fmt.Errorf(
			"credential is %q, expected a service_account key", meta.Type)
	}

	creds, err := google.CredentialsFromJSON(ctx, raw, scope)
	if err != nil {
		return nil, fmt.Errorf("build credentials: %w", err)
	}

	// oauth2's client fetches and refreshes the access token on its own; the
	// credential on disk is never sent anywhere, only exchanged for one.
	client := oauth2.NewClient(ctx, creds.TokenSource)
	client.Timeout = 20 * time.Second

	return &Sender{projectID: meta.ProjectID, client: client}, nil
}

func (s *Sender) ProjectID() string { return s.projectID }

// Message is one notification, as the user will see it.
type Message struct {
	Title string
	Body  string
	// Delivered alongside the notification so a tap can open the right screen.
	Data map[string]string
}

// Target identifies one registered app installation. New clients use a
// Firebase Installation ID; legacy token targeting stays available for older
// Android/iOS builds during Firebase's migration period.
type Target struct {
	Identifier string
	FID        bool
}

// Send delivers msg to every target, and reports the identifiers FCM says are
// dead so the caller can forget them.
//
// A failure for one device never stops the others: a stale token on an old
// phone must not silence the reminder on the current one.
func (s *Sender) Send(ctx context.Context, targets []Target, msg Message) (stale []string, err error) {
	var firstErr error
	for _, target := range targets {
		dead, err := s.sendOne(ctx, target, msg)
		switch {
		case dead:
			stale = append(stale, target.Identifier)
		case err != nil:
			slog.Error("push failed", "error", err)
			if firstErr == nil {
				firstErr = err
			}
		}
	}
	return stale, firstErr
}

// sendOne posts a single message. dead is true when FCM says the target no
// longer exists, which is a normal outcome after an uninstall.
func (s *Sender) sendOne(ctx context.Context, target Target, msg Message) (dead bool, err error) {
	targetField := "token"
	if target.FID {
		targetField = "fid"
	}
	payload := map[string]any{
		"message": map[string]any{
			targetField: target.Identifier,
			"notification": map[string]any{
				"title": msg.Title,
				"body":  msg.Body,
			},
			"data": msg.Data,
			"android": map[string]any{
				"priority": "high",
				"notification": map[string]any{
					// Groups the reminders into one channel the user can mute
					// without silencing the whole app.
					"channel_id": "fechamento",
				},
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return false, fmt.Errorf("encode message: %w", err)
	}

	url := fmt.Sprintf(
		"https://fcm.googleapis.com/v1/projects/%s/messages:send", s.projectID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url,
		bytes.NewReader(body))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return false, fmt.Errorf("send push: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return false, nil
	}

	detail, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
	// 404 UNREGISTERED and 400 on a malformed identifier both mean this target
	// will never work again.
	if resp.StatusCode == http.StatusNotFound ||
		bytes.Contains(detail, []byte("UNREGISTERED")) ||
		bytes.Contains(detail, []byte("INVALID_ARGUMENT")) {
		return true, nil
	}
	return false, fmt.Errorf("fcm returned %d: %s", resp.StatusCode, detail)
}
