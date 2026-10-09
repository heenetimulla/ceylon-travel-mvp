import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {defineString} from "firebase-functions/params";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {processDeletionOperation} from "./account_deletion";
const region = defineString("ACCOUNT_DELETION_REGION", {default: "asia-southeast1"});
const serviceAccount = defineString("ACCOUNT_DELETION_SERVICE_ACCOUNT");
async function tolerateMissing(action: () => Promise<unknown>): Promise<void> {
  try { await action(); } catch (error) {
    if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
  }
}
export const processAccountDeletion = onDocumentCreated({
  document: "account_deletion_requests/{uid}/operations/{operationId}", region, serviceAccount,
  retry: true, timeoutSeconds: 540, maxInstances: 3,
}, async event => {
  const auth = getAuth();
  await processDeletionOperation(getFirestore(), event.params.uid, event.params.operationId, {
    principal: async uid => {
      try {
        const user = await auth.getUser(uid);
        return {uid, admin: user.customClaims?.admin === true,
          supportAdmin: user.customClaims?.supportAdmin === true, disabled: user.disabled};
      } catch (error) {
        if ((error as {code?: string}).code === "auth/user-not-found") return {uid, admin: false, disabled: true};
        throw error;
      }
    },
    disable: async uid => {
      await tolerateMissing(() => auth.updateUser(uid, {disabled: true}));
      await tolerateMissing(() => auth.revokeRefreshTokens(uid));
    },
    deleteAuth: uid => tolerateMissing(() => auth.deleteUser(uid)),
  });
});
