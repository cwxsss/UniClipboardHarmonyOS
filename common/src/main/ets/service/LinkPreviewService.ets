import { http } from '@kit.NetworkKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { LinkPreview } from '../model/ClipboardModels';

export class LinkPreviewService {
  async load(url: string): Promise<LinkPreview> {
    if (deviceInfo.sdkApiVersion >= 24) {
      try {
        return await this.loadWithPreconnect(url);
      } catch (error) {
        console.warn('UniClipboard RCP preconnect failed, falling back to Network Kit HTTP.');
      }
    }
    return this.loadWithHttp(url);
  }

  private async loadWithPreconnect(url: string): Promise<LinkPreview> {
    let session: rcp.DefaultSession = rcp.getDefaultSession();
    let headers: rcp.RequestHeaders = {
      'user-agent': 'UniClipboardHarmonyOS/1.0',
      'accept': 'text/html,application/xhtml+xml'
    };
    let configuration: rcp.Configuration = {
      transfer: {
        autoRedirect: true,
        timeout: {
          connectMs: 8000,
          transferMs: 8000
        }
      }
    };
    let preconnectRequest: rcp.Request = new rcp.Request(url, 'GET', headers);
    preconnectRequest.configuration = configuration;
    preconnectRequest.connectOnly = true;
    await session.fetch(preconnectRequest);

    let contentRequest: rcp.Request = new rcp.Request(url, 'GET', headers);
    contentRequest.configuration = configuration;
    let response: rcp.Response = await session.fetch(contentRequest);
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw new Error('link preview response code: ' + response.statusCode.toString());
    }
    let html: string | null = response.toString();
    if (html === null) {
      throw new Error('link preview response is not text');
    }
    return this.parse(url, html);
  }

  private async loadWithHttp(url: string): Promise<LinkPreview> {
    let request: http.HttpRequest = http.createHttp();
    try {
      let response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'User-Agent': 'UniClipboardHarmonyOS/1.0',
          'Accept': 'text/html,application/xhtml+xml'
        },
        connectTimeout: 8000,
        readTimeout: 8000,
        maxLimit: 512 * 1024
      });
      if (response.responseCode < 200 || response.responseCode >= 400) {
        throw new Error('link preview response code: ' + response.responseCode.toString());
      }
      let html: string = response.result as string;
      return this.parse(url, html);
    } finally {
      request.destroy();
    }
  }

  private parse(url: string, html: string): LinkPreview {
    let title: string = this.readMeta(html, 'og:title');
    if (title.length === 0) {
      title = this.readMeta(html, 'twitter:title');
    }
    if (title.length === 0) {
      title = this.readTitle(html);
    }
    let description: string = this.readMeta(html, 'og:description');
    if (description.length === 0) {
      description = this.readMeta(html, 'description');
    }
    if (description.length === 0) {
      description = this.readMeta(html, 'twitter:description');
    }
    let imageUrl: string = this.readMeta(html, 'og:image');
    if (imageUrl.length === 0) {
      imageUrl = this.readMeta(html, 'twitter:image');
    }
    imageUrl = this.resolveUrl(url, imageUrl);
    let siteName: string = this.readMeta(html, 'og:site_name');
    if (siteName.length === 0) {
      siteName = this.host(url);
    }
    if (title.length === 0) {
      title = siteName;
    }
    return new LinkPreview(url, title, description, siteName, imageUrl);
  }

  private readMeta(html: string, key: string): string {
    let escapedKey: string = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    let propertyPattern: RegExp = new RegExp("<meta[^>]+(?:property|name)\\s*=\\s*[\\\"']" +
      escapedKey + "[\\\"'][^>]+content\\s*=\\s*[\\\"']([^\\\"']*)[\\\"'][^>]*>", 'i');
    let propertyMatch: RegExpMatchArray | null = html.match(propertyPattern);
    if (propertyMatch !== null && propertyMatch.length > 1) {
      return this.decode(propertyMatch[1].trim());
    }
    let contentFirstPattern: RegExp = new RegExp("<meta[^>]+content\\s*=\\s*[\\\"']([^\\\"']*)[\\\"'][^>]+(?:property|name)\\s*=\\s*[\\\"']" +
      escapedKey + "[\\\"'][^>]*>", 'i');
    let contentFirstMatch: RegExpMatchArray | null = html.match(contentFirstPattern);
    if (contentFirstMatch !== null && contentFirstMatch.length > 1) {
      return this.decode(contentFirstMatch[1].trim());
    }
    return '';
  }

  private readTitle(html: string): string {
    let match: RegExpMatchArray | null = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
    if (match === null || match.length < 2) {
      return '';
    }
    return this.decode(this.stripTags(match[1]).trim());
  }

  private stripTags(value: string): string {
    return value.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');
  }

  private decode(value: string): string {
    return value.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<').replace(/&gt;/g, '>');
  }

  private host(url: string): string {
    let start: number = url.indexOf('://');
    let hostStart: number = start >= 0 ? start + 3 : 0;
    let hostEnd: number = url.length;
    let slash: number = url.indexOf('/', hostStart);
    if (slash >= 0) {
      hostEnd = slash;
    }
    let query: number = url.indexOf('?', hostStart);
    if (query >= 0 && query < hostEnd) {
      hostEnd = query;
    }
    return url.substring(hostStart, hostEnd);
  }

  private resolveUrl(baseUrl: string, candidate: string): string {
    if (candidate.length === 0) {
      return '';
    }
    if (candidate.indexOf('https://') === 0 || candidate.indexOf('http://') === 0) {
      return candidate;
    }
    let schemeEnd: number = baseUrl.indexOf('://');
    let scheme: string = schemeEnd >= 0 ? baseUrl.substring(0, schemeEnd) : 'https';
    if (candidate.indexOf('//') === 0) {
      return scheme + ':' + candidate;
    }
    let originEnd: number = baseUrl.indexOf('/', schemeEnd >= 0 ? schemeEnd + 3 : 0);
    let origin: string = originEnd >= 0 ? baseUrl.substring(0, originEnd) : baseUrl;
    if (candidate.indexOf('/') === 0) {
      return origin + candidate;
    }
    let lastSlash: number = baseUrl.lastIndexOf('/');
    let directory: string = lastSlash >= 0 ? baseUrl.substring(0, lastSlash + 1) : baseUrl + '/';
    return directory + candidate;
  }
}
