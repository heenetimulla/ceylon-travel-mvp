import {strict as assert} from "node:assert";
import {test} from "node:test";
import {parseOperatorInput, updatedAdminClaims} from "../src/set_admin_claims";

test("grant preserves unrelated claims and sets both trusted administrator flags", () => {
  const existing = Object.freeze({admin: false, supportAdmin: false, region: "test-region", access: {reports: true}});
  assert.deepEqual(updatedAdminClaims("grant", existing), {...existing, admin: true, supportAdmin: true});
  assert.equal(existing.admin, false);
  assert.equal(existing.supportAdmin, false);
});

test("revoke removes only admin/supportAdmin and does not mutate the original", () => {
  const existing = Object.freeze({admin: true, supportAdmin: true, anotherRole: true, features: ["reports"]});
  const result = updatedAdminClaims("revoke", existing);
  assert.deepEqual(result, {anotherRole: true, features: ["reports"]});
  assert.equal(Object.hasOwn(result, "admin"), false);
  assert.equal(Object.hasOwn(result, "supportAdmin"), false);
  assert.equal(existing.admin, true);
});

test("absent claims and repeated grants/revokes are safe", () => {
  assert.deepEqual(updatedAdminClaims("grant", undefined), {admin: true, supportAdmin: true});
  assert.deepEqual(updatedAdminClaims("revoke", undefined), {});
  const granted = updatedAdminClaims("grant", {unrelated: "preserved"});
  assert.deepEqual(updatedAdminClaims("grant", granted), granted);
  const revoked = updatedAdminClaims("revoke", granted);
  assert.deepEqual(updatedAdminClaims("revoke", revoked), revoked);
});

test("CLI requires an explicit action, UID and project, with no extra arguments", () => {
  for (const action of ["grant", "revoke"]) {
    assert.deepEqual(parseOperatorInput([action, "test-uid"], "test-project"),
      {action, uid: "test-uid", projectId: "test-project"});
  }
  for (const args of [[], ["grant"], ["grant", "test-uid", "extra"]]) {
    assert.throws(() => parseOperatorInput(args, "test-project"), /Usage:/);
  }
  assert.throws(() => parseOperatorInput(["create", "test-uid"], "test-project"), /Unsupported action/);
  for (const uid of ["", "  ", "x".repeat(129), "test\nuid"]) {
    assert.throws(() => parseOperatorInput(["grant", uid], "test-project"), /valid Firebase Auth UID/);
  }
  for (const project of [undefined, "", "  "]) {
    assert.throws(() => parseOperatorInput(["grant", "test-uid"], project), /GOOGLE_CLOUD_PROJECT/);
  }
});
