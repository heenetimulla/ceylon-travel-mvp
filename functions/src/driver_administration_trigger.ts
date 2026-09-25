import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {defineSecret, defineString} from "firebase-functions/params";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {processRegistrationOperation} from "./registration_application";
import {processDriverOperation} from "./driver_administration";

const identityKey = defineSecret("DRIVER_IDENTITY_HMAC_KEY");
const region = defineString("DRIVER_ADMIN_REGION", {default: "asia-southeast1"});
// Use a dedicated least-privilege runtime identity; configured by the operator.
const serviceAccount = defineString("DRIVER_ADMIN_SERVICE_ACCOUNT");

export const processDriverAdministration = onDocumentCreated({
  document: "users/{uid}/driver_operations/{operationId}", region, serviceAccount,
  secrets: [identityKey], retry: true, timeoutSeconds: 120, maxInstances: 5,
}, async (event) => {
  await processDriverOperation(getFirestore(), event.params.uid, event.params.operationId, dependencies());
});

export const processRegistrationApplication = onDocumentCreated({
  document: "users/{uid}/application_operations/{operationId}", region, serviceAccount,
  secrets: [identityKey], retry: true, timeoutSeconds: 120, maxInstances: 5,
}, async (event) => {
  await processRegistrationOperation(getFirestore(), event.params.uid, event.params.operationId, dependencies());
});

function dependencies() {
  return {
    secret: identityKey.value(),
    evidenceMetadata: async (path: string) => {
      const [metadata] = await getStorage().bucket().file(path).getMetadata();
      const custom: {[key: string]: string} = {};
      for (const [key, value] of Object.entries(metadata.metadata ?? {})) {
        if (typeof value === "string") custom[key] = value;
      }
      return {contentType: metadata.contentType, size: metadata.size, timeCreated: metadata.timeCreated,
        generation: metadata.generation, metadata: custom};
    },
    principal: async (uid: string) => {
      try {
        const user = await getAuth().getUser(uid);
        return {uid: user.uid, admin: user.customClaims?.admin === true, disabled: user.disabled};
      } catch (error) {
        if ((error as {code?: string}).code === "auth/user-not-found") return {uid, admin: false, disabled: true};
        throw error;
      }
    },
  };
}
