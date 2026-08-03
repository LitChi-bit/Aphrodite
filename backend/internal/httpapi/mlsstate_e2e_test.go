package httpapi

import (
	"context"
	"net/http"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/mlsstate"
)

func TestMLSStateAPIEndToEnd(t *testing.T) {
	fixture := newMLSStateE2EFixture(t)
	commit := map[string]any{
		"epoch":      0,
		"group_info": "Z3JvdXAtaW5mby1leGFtcGxl",
		"commit":     "Y29tbWl0LWV4YW1wbGU",
		"welcomes": []map[string]any{{
			"target_account_id": fixture.targetAccountID,
			"target_device_id":  fixture.targetDeviceID,
			"welcome":           "d2VsY29tZS1leGFtcGxl",
		}},
	}
	response := fixture.request(t, fixture.adminToken, http.MethodPut, "/v1/conversations/"+fixture.conversationID+"/mls/state", commit)
	if response.Code != http.StatusCreated {
		t.Fatalf("commit status = %d body = %s", response.Code, response.Body.String())
	}

	response = fixture.request(t, fixture.targetToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/state", nil)
	assertChatE2EError(t, response, http.StatusNotFound, "not_found")

	response = fixture.request(t, fixture.targetToken, http.MethodPost, "/v1/mls/welcomes:claim", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("welcome claim status = %d body = %s", response.Code, response.Body.String())
	}
	var claimed struct {
		Data []welcomeResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &claimed)
	if len(claimed.Data) != 1 || claimed.Data[0].ConversationID != fixture.conversationID || claimed.Data[0].Epoch != 0 || claimed.Data[0].Welcome != "d2VsY29tZS1leGFtcGxl" {
		t.Fatalf("unexpected claimed welcome: %#v", claimed.Data)
	}

	response = fixture.request(t, fixture.targetToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/state", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("claimed member state status = %d body = %s", response.Code, response.Body.String())
	}
	var state struct {
		Data groupStateResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &state)
	if state.Data.Epoch != 0 || state.Data.GroupInfo != "Z3JvdXAtaW5mby1leGFtcGxl" || state.Data.CommitData != "Y29tbWl0LWV4YW1wbGU" {
		t.Fatalf("unexpected MLS state: %#v", state.Data)
	}

	response = fixture.request(t, fixture.targetToken, http.MethodPost, "/v1/mls/welcomes:claim", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("repeat welcome claim status = %d body = %s", response.Code, response.Body.String())
	}
	var empty struct {
		Data []welcomeResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &empty)
	if len(empty.Data) != 0 {
		t.Fatalf("repeated claim returned %d welcomes", len(empty.Data))
	}

	response = fixture.request(t, fixture.outsiderToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/state", nil)
	assertChatE2EError(t, response, http.StatusNotFound, "not_found")

	var activeMembers int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM conversation_members WHERE conversation_id = $1 AND account_id = $2 AND left_at IS NULL`, fixture.conversationID, fixture.targetAccountID).Scan(&activeMembers); err != nil {
		t.Fatalf("check activated member: %v", err)
	}
	if activeMembers != 1 {
		t.Fatalf("activated members = %d, want 1", activeMembers)
	}
	var forbiddenColumns int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('mls_group_states', 'mls_welcome_deliveries') AND column_name IN ('private_key', 'group_secret', 'plaintext', 'decrypted_text')`).Scan(&forbiddenColumns); err != nil {
		t.Fatalf("check MLS state columns: %v", err)
	}
	if forbiddenColumns != 0 {
		t.Fatalf("MLS state tables expose %d prohibited columns", forbiddenColumns)
	}
}

type mlsStateE2EFixture struct {
	chatE2EFixture
	conversationID  string
	targetAccountID string
	targetDeviceID  string
	adminToken      string
	targetToken     string
}

func newMLSStateE2EFixture(t *testing.T) mlsStateE2EFixture {
	t.Helper()
	base := newChatE2EFixture(t)
	const conversationID = "10000000-0000-4000-8000-000000000001"
	const adminAccountID = "30000000-0000-4000-8000-000000000001"
	const adminDeviceID = "40000000-0000-4000-8000-000000000001"
	const adminSessionID = "50000000-0000-4000-8000-000000000001"
	const targetAccountID = "30000000-0000-4000-8000-000000000004"
	const targetDeviceID = "40000000-0000-4000-8000-000000000004"
	const targetSessionID = "50000000-0000-4000-8000-000000000004"
	const outsiderAccountID = "30000000-0000-4000-8000-000000000003"
	const outsiderDeviceID = "40000000-0000-4000-8000-000000000003"
	const outsiderSessionID = "50000000-0000-4000-8000-000000000003"

	now := time.Now().UTC().Truncate(time.Second)
	if _, err := base.pool.Exec(context.Background(), `INSERT INTO accounts (id, username, email, display_name, password_hash, status, created_at, updated_at) VALUES ($1,'mls-target','mls-target@example.test','MLS target','e2e-test-password-hash','active',$2,$2)`, targetAccountID, now); err != nil {
		t.Fatalf("insert MLS target account: %v", err)
	}
	if _, err := base.pool.Exec(context.Background(), `INSERT INTO devices (id, account_id, name, platform, identity_public_key, created_at, updated_at) VALUES ($1,$2,'MLS target device','android',$3,$4,$4)`, targetDeviceID, targetAccountID, []byte("mls-e2e-public-key"), now); err != nil {
		t.Fatalf("insert MLS target device: %v", err)
	}
	if _, err := base.pool.Exec(context.Background(), `INSERT INTO auth_sessions (id, account_id, device_id, expires_at, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$5)`, targetSessionID, targetAccountID, targetDeviceID, now.Add(time.Hour), now); err != nil {
		t.Fatalf("insert MLS target session: %v", err)
	}
	if _, err := base.pool.Exec(context.Background(), `UPDATE conversation_members SET role = 'admin' WHERE conversation_id = $1 AND account_id = $2`, conversationID, adminAccountID); err != nil {
		t.Fatalf("promote MLS admin: %v", err)
	}

	issuer, verifier := newMLSStateE2ETokenPair(t)
	adminToken, err := issuer.IssueAccessToken(adminAccountID, adminDeviceID, adminSessionID, now.Add(time.Hour))
	if err != nil {
		t.Fatalf("issue admin token: %v", err)
	}
	targetToken, err := issuer.IssueAccessToken(targetAccountID, targetDeviceID, targetSessionID, now.Add(time.Hour))
	if err != nil {
		t.Fatalf("issue target token: %v", err)
	}
	outsiderToken, err := issuer.IssueAccessToken(outsiderAccountID, outsiderDeviceID, outsiderSessionID, now.Add(time.Hour))
	if err != nil {
		t.Fatalf("issue outsider token: %v", err)
	}
	repository := auth.NewPostgresRepository(base.pool)
	service, err := auth.NewService(auth.Dependencies{Accounts: repository, Devices: repository, Challenges: repository, Sessions: repository, Passwords: auth.BcryptPasswordVerifier{}, Hasher: auth.SHA256TokenHasher{}, Credentials: auth.SecureCredentialGenerator{}, IDs: auth.RandomIDGenerator{}, AccessTokens: issuer})
	if err != nil {
		t.Fatalf("create MLS auth service: %v", err)
	}
	server := NewServer(discardLogger(), WithMLSStateService(mlsstate.NewPostgresRepository(base.pool), service, verifier))
	return mlsStateE2EFixture{chatE2EFixture: chatE2EFixture{pool: base.pool, handler: server.Handler(), outsiderToken: outsiderToken}, conversationID: conversationID, targetAccountID: targetAccountID, targetDeviceID: targetDeviceID, adminToken: adminToken, targetToken: targetToken}
}
