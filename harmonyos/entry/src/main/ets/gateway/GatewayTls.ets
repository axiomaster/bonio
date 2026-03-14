import { hilog } from '@kit.PerformanceAnalysisKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

/**
 * GatewayTls — TLS fingerprint pinning and Trust On First Use (TOFU).
 * Port of Android's GatewayTls.kt.
 *
 * Provides:
 * - normalizeFingerprint: normalizes SHA-256 fingerprint strings
 * - sha256Hex: computes SHA-256 hex digest
 * - probeGatewayTlsFingerprint: probes a TLS server and returns its cert fingerprint
 * - shouldAcceptFingerprint: TOFU / pinning logic
 */

const TAG = 'GatewayTls';
const DOMAIN = 0x3D00;

export interface GatewayTlsParams {
  required: boolean;
  expectedFingerprint: string | undefined;
  allowTOFU: boolean;
  stableId: string;
}

/**
 * Normalize a TLS fingerprint string:
 * - Strip "sha256:" or "sha-256:" prefix
 * - Lowercase
 * - Remove non-hex characters
 */
export function normalizeFingerprint(raw: string): string {
  let stripped = raw.trim()
    .replace(/^sha-?256\s*:?\s*/i, '');
  return stripped.toLowerCase().replace(/[^0-9a-f]/g, '');
}

/**
 * Compute SHA-256 hex digest of binary data.
 */
export async function sha256Hex(data: Uint8Array): Promise<string> {
  try {
    const md = cryptoFramework.createMd('SHA256');
    const blob: cryptoFramework.DataBlob = { data: data };
    await md.update(blob);
    const digest = await md.digest();
    return uint8ArrayToHex(digest.data);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'sha256Hex failed: %{public}s', String(e));
    throw new Error('sha256Hex failed: ' + String(e));
  }
}

/**
 * Synchronous SHA-256 hex for string input.
 */
export function sha256HexSync(data: string): string {
  const encoder = new util.TextEncoder();
  const bytes = encoder.encodeInto(data);
  // Use crypto framework sync approach
  const md = cryptoFramework.createMd('SHA256');
  const blob: cryptoFramework.DataBlob = { data: bytes };
  md.updateSync(blob);
  const digest = md.digestSync();
  return uint8ArrayToHex(digest.data);
}

function uint8ArrayToHex(arr: Uint8Array): string {
  const hexArr: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    const hex = arr[i].toString(16);
    hexArr.push(hex.length === 1 ? `0${hex}` : hex);
  }
  return hexArr.join('');
}

/**
 * Determine whether to accept a TLS connection based on pinning/TOFU policy.
 *
 * @param params - TLS parameters (expected fingerprint, TOFU, etc.)
 * @param serverFingerprint - The actual fingerprint from the server
 * @param onStore - Callback to store the fingerprint on TOFU acceptance
 * @returns true if the connection should be accepted
 */
export function shouldAcceptFingerprint(
  params: GatewayTlsParams,
  serverFingerprint: string,
  onStore?: (fingerprint: string) => void
): boolean {
  const normalizedServer = normalizeFingerprint(serverFingerprint);

  if (params.expectedFingerprint) {
    const expected = normalizeFingerprint(params.expectedFingerprint);
    if (normalizedServer !== expected) {
      hilog.error(DOMAIN, TAG,
        'TLS fingerprint mismatch. Expected: %{public}s, Got: %{public}s',
        expected.substring(0, 16) + '...', normalizedServer.substring(0, 16) + '...');
      return false;
    }
    return true;
  }

  if (params.allowTOFU) {
    hilog.info(DOMAIN, TAG, 'TOFU: accepting and storing fingerprint for %{public}s', params.stableId);
    if (onStore) {
      onStore(normalizedServer);
    }
    return true;
  }

  // No pinning, no TOFU — reject self-signed certs
  return false;
}

/**
 * Probe a TLS server and return its certificate's SHA-256 fingerprint.
 * Uses a TLS socket connection to extract the server certificate.
 *
 * @param host - The server hostname or IP
 * @param port - The server port
 * @param timeoutMs - Connection timeout in milliseconds
 * @returns The hex-encoded SHA-256 fingerprint, or undefined on failure
 */
export async function probeGatewayTlsFingerprint(
  host: string,
  port: number,
  timeoutMs: number = 3000
): Promise<string | undefined> {
  const trimmedHost = host.trim();
  if (trimmedHost.length === 0) return undefined;
  if (port < 1 || port > 65535) return undefined;

  try {
    // Create TLS socket
    const tlsSocket = socket.constructTLSSocketInstance();
    try {
      // Connect with TLS
      await tlsSocket.connect({
        address: {
          address: trimmedHost,
          port: port,
          family: 1, // IPv4
        },
        secureOptions: {
          // Accept all certs for probing (we just want the fingerprint)
        },
      });

      // Get remote certificate
      const certData = await tlsSocket.getRemoteCertificate();
      if (!certData || !certData.data) {
        hilog.warn(DOMAIN, TAG, 'probeFingerprint: no remote certificate');
        return undefined;
      }

      // Compute fingerprint from cert DER data
      const certBytes = typeof certData.data === 'string'
        ? new util.TextEncoder().encodeInto(certData.data)
        : certData.data as Uint8Array;
      const fingerprint = await sha256Hex(certBytes);
      hilog.info(DOMAIN, TAG, 'probeFingerprint: %{public}s:%{public}d → %{public}s',
        trimmedHost, port, fingerprint.substring(0, 16) + '...');
      return fingerprint;
    } finally {
      try {
        tlsSocket.close();
      } catch (_e) {
        // ignore cleanup errors
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'probeFingerprint failed for %{public}s:%{public}d: %{public}s',
      trimmedHost, port, String(e));
    return undefined;
  }
}
