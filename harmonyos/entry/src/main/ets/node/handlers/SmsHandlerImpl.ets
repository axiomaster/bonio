import { sms } from '@kit.TelephonyKit';
import { InvokeResult, InvokeError } from '../../gateway/GatewaySession';
import { SmsHandler } from '../InvokeDispatcher';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';

export class SmsHandlerImpl implements SmsHandler {
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async handleSmsSend(paramsJson: string | undefined): Promise<InvokeResult> {
    try {
      if (!paramsJson) {
        return this.makeError("INVALID_REQUEST", "INVALID_REQUEST: paramsJSON required");
      }

      const params = JSON.parse(paramsJson) as Record<string, string>;
      const to = params['to'];
      const message = params['message'];

      if (!to || to.trim() === '') {
        return this.makeError("INVALID_REQUEST", "INVALID_REQUEST: 'to' phone number required");
      }
      if (!message || message.trim() === '') {
        return this.makeError("INVALID_REQUEST", "INVALID_REQUEST: 'message' text required");
      }

      /* 
      // ohos.permission.SEND_MESSAGES removed as it is system_basic
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenID = this.context.applicationInfo.accessTokenId;
      const status = await atManager.checkAccessToken(tokenID, "ohos.permission.SEND_MESSAGES");
      
      if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
         return this.makeError("SMS_PERMISSION_REQUIRED", `SMS_PERMISSION_REQUIRED: ohos.permission.SEND_MESSAGES not granted. Status: ${status}`);
      }
      */
      
      const hasTelephony = sms.hasSmsCapability();
      if (!hasTelephony) {
         return this.makeError("SMS_UNAVAILABLE", "SMS_UNAVAILABLE: telephony not available");
      }

      return new Promise((resolve) => {
        let isResolved = false;

        const sendCallback = (err: Error, data: sms.ISendShortMessageCallback) => {
          if (isResolved) return;
          isResolved = true;

          if (err) {
            resolve(this.makeError("SMS_SEND_FAILED", `SMS_SEND_FAILED: ${err.message}`));
          } else if (data.result === sms.SendSmsResult.SEND_SMS_SUCCESS) {
            resolve({ ok: true, payloadJson: JSON.stringify({ ok: true, to: to }) });
          } else {
            resolve(this.makeError("SMS_SEND_FAILED", `SMS_SEND_FAILED: failed with result code ${data.result}`));
          }
        };

        const deliveryCallback = (err: Error, data: sms.IDeliveryShortMessageCallback) => {
           // We mostly care about sendCallback to report back to gateway
        };

        const options: sms.SendMessageOptions = {
          slotId: 0, // default SIM
          destinationHost: to,
          content: message,
          sendCallback: sendCallback,
          deliveryCallback: deliveryCallback
        };

        sms.sendShortMessage(options, (err: Error) => {
          if (err && !isResolved) {
             isResolved = true;
             resolve(this.makeError("SMS_SEND_FAILED", `SMS_SEND_FAILED: ${err.message}`));
          }
        });
      });
      
    } catch (e) {
      return this.makeError("INTERNAL_ERROR", e instanceof Error ? e.message : String(e));
    }
  }

  private makeError(code: string, message: string): InvokeResult {
    const err: InvokeError = { code: code, message: message };
    return { ok: false, error: err };
  }
}
