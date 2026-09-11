// Operator-only CLI. Never import/export this from the Functions entry point.
import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";

export type AdminClaimAction = "grant" | "revoke";

class OperatorError extends Error {}

export function parseOperatorInput(args: readonly string[], project: string | undefined): {
  action: AdminClaimAction; uid: string; projectId: string;
} {
  if (args.length !== 2) {
    throw new OperatorError("Usage: node lib/src/set_admin_claims.js <grant|revoke> <UID>");
  }
  const [action, uid] = args;
  if (action !== "grant" && action !== "revoke") {
    throw new OperatorError("Unsupported action. Use grant or revoke.");
  }
  if (!uid.trim() || uid.length > 128 || /[\u0000-\u001f\u007f-\u009f]/u.test(uid)) {
    throw new OperatorError("An explicit valid Firebase Auth UID is required (1-128 characters, no control characters).");
  }
  const projectId = project?.trim();
  if (!projectId) throw new OperatorError("Set GOOGLE_CLOUD_PROJECT explicitly before running this script.");
  return {action, uid, projectId};
}

// Copy existing claims; never replace them with only the two administrator flags.
export function updatedAdminClaims(action: AdminClaimAction,
  existing: Readonly<Record<string, unknown>> | undefined): Record<string, unknown> {
  const claims = {...existing};
  if (action === "grant") {
    claims.admin = true;
    claims.supportAdmin = true;
  } else {
    delete claims.admin;
    delete claims.supportAdmin;
  }
  return claims;
}

function safeAuthError(error: unknown): OperatorError {
  const code = typeof error === "object" && error !== null && "code" in error ? error.code : undefined;
  if (code === "auth/user-not-found") {
    return new OperatorError("Firebase Auth user does not exist in the selected project. No user was created.");
  }
  if (code === "auth/insufficient-permission") {
    return new OperatorError("Operator credentials lack permission to read users or update custom claims in this project.");
  }
  return new OperatorError("Could not update custom claims. Check the project, ADC permissions, connectivity and existing claims payload limits.");
}

async function main(): Promise<void> {
  const {action, uid, projectId} = parseOperatorInput(process.argv.slice(2), process.env.GOOGLE_CLOUD_PROJECT);
  let credential: ReturnType<typeof applicationDefault>;
  try {
    credential = applicationDefault();
    // Fail before any Auth operation when ADC cannot obtain a token. Never log it.
    await credential.getAccessToken();
  } catch {
    throw new OperatorError("Application Default Credentials are unavailable or invalid. Configure trusted operator ADC first.");
  }
  const app = initializeApp({projectId, credential});
  try {
    const auth = getAuth(app);
    const user = await auth.getUser(uid);
    await auth.setCustomUserClaims(uid, updatedAdminClaims(action, user.customClaims));
  } catch (error: unknown) {
    throw safeAuthError(error);
  } finally {
    await deleteApp(app);
  }
  console.log(`Admin claims ${action === "grant" ? "granted" : "revoked"} ${action === "grant" ? "to" : "from"} UID: ${uid}`);
}

// Importing pure helpers in tests does not initialize an app or access credentials.
if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error instanceof OperatorError ? error.message : "Admin claim operation failed. Check trusted operator configuration.");
    process.exitCode = 1;
  });
}
