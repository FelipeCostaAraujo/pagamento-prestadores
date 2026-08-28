package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/felipearaujo/diarias/backend/internal/config"
)

func TestRefreshEndpointIsPublicAndValidatesItsCredential(t *testing.T) {
	// A nil store is enough here because an empty credential must be rejected
	// before persistence is touched. If the route accidentally moves behind
	// requireSession, this returns 401 rather than the expected validation 400.
	handler := NewHandler(nil, config.Config{CORSOrigins: []string{"*"}})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh",
		strings.NewReader(`{}`))
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d; body=%s",
			rec.Code, http.StatusBadRequest, rec.Body.String())
	}
	var body errorBody
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Code != "invalid_request" {
		t.Errorf("code = %q, want invalid_request", body.Code)
	}
}
