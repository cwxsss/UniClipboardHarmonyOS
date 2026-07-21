import { ConnectPayload, parseConnectUri } from 'uniclipboard_native';
import { ServerConfig } from '../model/ClipboardModels';

export class NativeProtocolService {
  parseServerConfig(uri: string): ServerConfig {
    let payload: ConnectPayload = parseConnectUri(uri.trim());
    let baseUrl: string = payload.url;
    if (payload.urls.length > 0) {
      baseUrl = payload.urls[0];
    }
    let config: ServerConfig = {
      baseUrl: baseUrl,
      username: payload.user,
      password: payload.pwd
    };
    return config;
  }
}
