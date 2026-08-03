package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
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

	var pendingRoster int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM mls_device_roster WHERE conversation_id = $1 AND account_id = $2 AND device_id = $3 AND status = 'pending'`, fixture.conversationID, fixture.targetAccountID, fixture.targetDeviceID).Scan(&pendingRoster); err != nil {
		t.Fatalf("check pending MLS roster: %v", err)
	}
	if pendingRoster != 1 {
		t.Fatalf("pending MLS roster entries = %d, want 1", pendingRoster)
	}

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
	var activeRoster int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM mls_device_roster WHERE conversation_id = $1 AND account_id = $2 AND device_id = $3 AND status = 'active'`, fixture.conversationID, fixture.targetAccountID, fixture.targetDeviceID).Scan(&activeRoster); err != nil {
		t.Fatalf("check active MLS roster: %v", err)
	}
	if activeRoster != 1 {
		t.Fatalf("active MLS roster entries = %d, want 1", activeRoster)
	}
	addSecondDevice := map[string]any{
		"epoch":      1,
		"group_info": "Z3JvdXAtaW5mby1lcG9jaC0x",
		"commit":     "Y29tbWl0LWVwb2NoLTE",
		"welcomes": []map[string]any{{
			"target_account_id": fixture.targetAccountID,
			"target_device_id":  fixture.secondTargetDeviceID,
			"welcome":           "c2Vjb25kLWRldmljZS13ZWxjb21l",
		}},
	}
	response = fixture.request(t, fixture.adminToken, http.MethodPut, "/v1/conversations/"+fixture.conversationID+"/mls/state", addSecondDevice)
	if response.Code != http.StatusCreated {
		t.Fatalf("second device commit status = %d body = %s", response.Code, response.Body.String())
	}
	response = fixture.request(t, fixture.secondTargetToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/state", nil)
	assertChatE2EError(t, response, http.StatusNotFound, "not_found")
	response = fixture.request(t, fixture.secondTargetToken, http.MethodPost, "/v1/mls/welcomes:claim", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("second device welcome claim status = %d body = %s", response.Code, response.Body.String())
	}
	response = fixture.request(t, fixture.secondTargetToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/state", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("second active device state status = %d body = %s", response.Code, response.Body.String())
	}

	proposalRequest := map[string]any{"base_epoch": 1, "proposal": "cHJvcG9zYWwtZXhhbXBsZQ"}
	response = fixture.request(t, fixture.secondTargetToken, http.MethodPost, "/v1/conversations/"+fixture.conversationID+"/mls/proposals", proposalRequest)
	if response.Code != http.StatusCreated {
		t.Fatalf("proposal publish status = %d body = %s", response.Code, response.Body.String())
	}
	var publishedProposal struct {
		Data proposalResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &publishedProposal)
	if publishedProposal.Data.Proposal != "cHJvcG9zYWwtZXhhbXBsZQ" || publishedProposal.Data.BaseEpoch != 1 {
		t.Fatalf("unexpected proposal: %#v", publishedProposal.Data)
	}
	response = fixture.request(t, fixture.adminToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/proposals", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("proposal list status = %d body = %s", response.Code, response.Body.String())
	}

	removeFirstDevice := map[string]any{
		"epoch":              2,
		"group_info":         "Z3JvdXAtaW5mby1lcG9jaC0y",
		"commit":             "Y29tbWl0LWVwb2NoLTI",
		"removed_device_ids": []string{fixture.targetDeviceID},
		"proposal_ids":       []string{publishedProposal.Data.ID},
	}
	response = fixture.request(t, fixture.adminToken, http.MethodPut, "/v1/conversations/"+fixture.conversationID+"/mls/state", removeFirstDevice)
	if response.Code != http.StatusCreated {
		t.Fatalf("remove device commit status = %d body = %s", response.Code, response.Body.String())
	}
	response = fixture.request(t, fixture.targetToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/state", nil)
	assertChatE2EError(t, response, http.StatusNotFound, "not_found")
	response = fixture.request(t, fixture.secondTargetToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/state", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("remaining device state status = %d body = %s", response.Code, response.Body.String())
	}
	response = fixture.request(t, fixture.adminToken, http.MethodGet, "/v1/conversations/"+fixture.conversationID+"/mls/proposals", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("consumed proposal list status = %d body = %s", response.Code, response.Body.String())
	}
	var consumedList struct {
		Data []proposalResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &consumedList)
	if len(consumedList.Data) != 0 {
		t.Fatalf("consumed proposal list returned %d items", len(consumedList.Data))
	}

	concurrentProposalRequest := map[string]any{"base_epoch": 2, "proposal": "Y29uY3VycmVudC1wcm9wb3NhbA"}
	response = fixture.request(t, fixture.secondTargetToken, http.MethodPost, "/v1/conversations/"+fixture.conversationID+"/mls/proposals", concurrentProposalRequest)
	if response.Code != http.StatusCreated {
		t.Fatalf("concurrent proposal publish status = %d body = %s", response.Code, response.Body.String())
	}
	var concurrentProposal struct {
		Data proposalResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &concurrentProposal)
	staleProposalRequest := map[string]any{"base_epoch": 2, "proposal": "c3RhbGUtcHJvcG9zYWw"}
	response = fixture.request(t, fixture.secondTargetToken, http.MethodPost, "/v1/conversations/"+fixture.conversationID+"/mls/proposals", staleProposalRequest)
	if response.Code != http.StatusCreated {
		t.Fatalf("stale proposal publish status = %d body = %s", response.Code, response.Body.String())
	}
	var staleProposal struct {
		Data proposalResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &staleProposal)

	concurrentCommit := map[string]any{
		"epoch":        3,
		"group_info":   "Z3JvdXAtaW5mby1lcG9jaC0z",
		"commit":       "Y29tbWl0LWVwb2NoLTM",
		"proposal_ids": []string{concurrentProposal.Data.ID},
	}
	statuses := fixture.concurrentRequests(t, fixture.adminToken, http.MethodPut, "/v1/conversations/"+fixture.conversationID+"/mls/state", concurrentCommit, 2)
	created, conflicted := 0, 0
	for _, status := range statuses {
		switch status {
		case http.StatusCreated:
			created++
		case http.StatusConflict:
			conflicted++
		default:
			t.Fatalf("unexpected concurrent commit statuses: %v", statuses)
		}
	}
	if created != 1 || conflicted != 1 {
		t.Fatalf("concurrent commit statuses = %v, want one 201 and one 409", statuses)
	}
	var expiredProposal int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM mls_proposals WHERE id = $1 AND expired_at IS NOT NULL AND expired_epoch = 3`, staleProposal.Data.ID).Scan(&expiredProposal); err != nil {
		t.Fatalf("check expired MLS proposal: %v", err)
	}
	if expiredProposal != 1 {
		t.Fatalf("expired MLS proposals = %d, want 1", expiredProposal)
	}

	var removedRoster int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM mls_device_roster WHERE conversation_id = $1 AND device_id = $2 AND status = 'removed'`, fixture.conversationID, fixture.targetDeviceID).Scan(&removedRoster); err != nil {
		t.Fatalf("check removed MLS roster: %v", err)
	}
	if removedRoster != 1 {
		t.Fatalf("removed MLS roster entries = %d, want 1", removedRoster)
	}
	var forbiddenColumns int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('mls_group_states', 'mls_welcome_deliveries', 'mls_device_roster') AND column_name IN ('private_key', 'group_secret', 'plaintext', 'decrypted_text')`).Scan(&forbiddenColumns); err != nil {
		t.Fatalf("check MLS state columns: %v", err)
	}
	if forbiddenColumns != 0 {
		t.Fatalf("MLS state tables expose %d prohibited columns", forbiddenColumns)
	}
}

type mlsStateE2EFixture struct {
	chatE2EFixture
	conversationID       string
	targetAccountID      string
	targetDeviceID       string
	secondTargetDeviceID string
	adminToken           string
	targetToken          string
	secondTargetToken    string
}

func (fixture mlsStateE2EFixture) concurrentRequests(t *testing.T, token, method, path string, body any, count int) []int {
	t.Helper()
	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal concurrent request: %v", err)
	}
	statuses := make([]int, count)
	var wait sync.WaitGroup
	start := make(chan struct{})
	for index := 0; index < count; index++ {
		wait.Add(1)
		go func(index int) {
			defer wait.Done()
			<-start
			request := httptest.NewRequest(method, path, bytes.NewReader(encoded))
			request.Header.Set("Authorization", "Bearer "+token)
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			fixture.handler.ServeHTTP(response, request)
			statuses[index] = response.Code
		}(index)
	}
	close(start)
	wait.Wait()
	return statuses
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
	const secondTargetDeviceID = "40000000-0000-4000-8000-000000000005"
	const secondTargetSessionID = "50000000-0000-4000-8000-000000000005"
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
	if _, err := base.pool.Exec(context.Background(), `INSERT INTO devices (id, account_id, name, platform, identity_public_key, created_at, updated_at) VALUES ($1,$2,'MLS target second device','android',$3,$4,$4)`, secondTargetDeviceID, targetAccountID, []byte("mls-e2e-second-public-key"), now); err != nil {
		t.Fatalf("insert MLS target second device: %v", err)
	}
	if _, err := base.pool.Exec(context.Background(), `INSERT INTO auth_sessions (id, account_id, device_id, expires_at, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$5)`, secondTargetSessionID, targetAccountID, secondTargetDeviceID, now.Add(time.Hour), now); err != nil {
		t.Fatalf("insert MLS target second session: %v", err)
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
	secondTargetToken, err := issuer.IssueAccessToken(targetAccountID, secondTargetDeviceID, secondTargetSessionID, now.Add(time.Hour))
	if err != nil {
		t.Fatalf("issue second target token: %v", err)
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
	return mlsStateE2EFixture{chatE2EFixture: chatE2EFixture{pool: base.pool, handler: server.Handler(), outsiderToken: outsiderToken}, conversationID: conversationID, targetAccountID: targetAccountID, targetDeviceID: targetDeviceID, secondTargetDeviceID: secondTargetDeviceID, adminToken: adminToken, targetToken: targetToken, secondTargetToken: secondTargetToken}
}
