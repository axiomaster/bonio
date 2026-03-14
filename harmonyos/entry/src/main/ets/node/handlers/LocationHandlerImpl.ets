import { geoLocationManager } from '@kit.LocationKit';
import { InvokeResult, InvokeError } from '../../gateway/GatewaySession';
import { LocationHandler } from '../InvokeDispatcher';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';

interface LocationPayload {
  ok: boolean;
  lat: number;
  lon: number;
  acc: number;
  ts: number;
  prv: string;
}

export class LocationHandlerImpl implements LocationHandler {
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async handleLocationGet(paramsJson: string | undefined): Promise<InvokeResult> {
    try {
      // Check permission
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenID = this.context.applicationInfo.accessTokenId;
      const statusApprox = await atManager.checkAccessToken(tokenID, "ohos.permission.APPROXIMATELY_LOCATION");
      // ohos.permission.LOCATION removed as it is system_basic
      
      if (statusApprox !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
         return this.makeError("LOCATION_PERMISSION_REQUIRED", `LOCATION_PERMISSION_REQUIRED: ohos.permission.APPROXIMATELY_LOCATION not granted.`);
      }

      const requestInfo: geoLocationManager.CurrentLocationRequest = {
          'priority': geoLocationManager.LocationRequestPriority.FIRST_FIX,
          'scenario': geoLocationManager.LocationRequestScenario.UNSET,
          'timeoutMs': 10000
      };

      const location = await geoLocationManager.getCurrentLocation(requestInfo);

      const payload: LocationPayload = {
        ok: true,
        lat: location.latitude,
        lon: location.longitude,
        acc: location.accuracy,
        ts: location.timeStamp,
        prv: "ohos.LocationKit"
      };

      return { ok: true, payloadJson: JSON.stringify(payload) };
      
    } catch (e) {
      return this.makeError("LOCATION_GET_FAILED", e instanceof Error ? e.message : String(e));
    }
  }

  private makeError(code: string, message: string): InvokeResult {
    const err: InvokeError = { code: code, message: message };
    return { ok: false, error: err };
  }
}
