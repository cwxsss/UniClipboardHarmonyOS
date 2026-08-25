import { CommonModifier } from '@kit.ArkUI';
import { ClipboardFeatureController } from 'clipboard_feature';

enum Api26MaterialRole {
  PANEL = 0,
  INTERACTIVE = 1,
  FLOATING = 2,
  INPUT = 3,
  MEDIA = 4,
  ACCENT = 5,
  NAVIGATION = 6,
  NAVIGATION_SELECTED = 7,
  SUBTLE = 8,
  ACCENT_SURFACE = 9
}

export class Api26MaterialModifier extends CommonModifier {
  private role: Api26MaterialRole = Api26MaterialRole.PANEL;
  private controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();

  constructor(role: Api26MaterialRole) {
    super();
    this.role = role;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    // API 26 system material is unavailable when compiling against API 24.
  }
}

export class Api26Material {
  private static materialSignature: string = '';
  private static panelModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.PANEL);
  private static interactiveModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.INTERACTIVE);
  private static floatingModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.FLOATING);
  private static inputModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.INPUT);
  private static mediaModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.MEDIA);
  private static accentModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.ACCENT);
  private static navigationModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.NAVIGATION);
  private static navigationSelectedModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.NAVIGATION_SELECTED);
  private static subtleModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.SUBTLE);
  private static accentSurfaceModifier: Api26MaterialModifier =
    new Api26MaterialModifier(Api26MaterialRole.ACCENT_SURFACE);

  private static refreshModifiers(): void {
    let controller: ClipboardFeatureController = ClipboardFeatureController.getInstance();
    let signature: string = controller.appearanceThemeId + ':' +
      controller.appearanceComponentMaterialStyle.toString();
    if (Api26Material.materialSignature === signature) {
      return;
    }
    Api26Material.materialSignature = signature;
    Api26Material.panelModifier = new Api26MaterialModifier(Api26MaterialRole.PANEL);
    Api26Material.interactiveModifier = new Api26MaterialModifier(Api26MaterialRole.INTERACTIVE);
    Api26Material.floatingModifier = new Api26MaterialModifier(Api26MaterialRole.FLOATING);
    Api26Material.inputModifier = new Api26MaterialModifier(Api26MaterialRole.INPUT);
    Api26Material.mediaModifier = new Api26MaterialModifier(Api26MaterialRole.MEDIA);
    Api26Material.accentModifier = new Api26MaterialModifier(Api26MaterialRole.ACCENT);
    Api26Material.navigationModifier = new Api26MaterialModifier(Api26MaterialRole.NAVIGATION);
    Api26Material.navigationSelectedModifier = new Api26MaterialModifier(Api26MaterialRole.NAVIGATION_SELECTED);
    Api26Material.subtleModifier = new Api26MaterialModifier(Api26MaterialRole.SUBTLE);
    Api26Material.accentSurfaceModifier = new Api26MaterialModifier(Api26MaterialRole.ACCENT_SURFACE);
  }

  public static panel(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.panelModifier;
  }

  public static interactive(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.interactiveModifier;
  }

  public static floating(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.floatingModifier;
  }

  public static input(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.inputModifier;
  }

  public static media(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.mediaModifier;
  }

  public static accent(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.accentModifier;
  }

  public static accentTextColor(): ResourceColor {
    return $r('app.color.on_accent');
  }

  public static cardBackgroundColor(): ResourceColor {
    return $r('app.color.surface');
  }

  public static subtle(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.subtleModifier;
  }

  public static accentSurface(): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    return Api26Material.accentSurfaceModifier;
  }

  public static navigation(selected: boolean): Api26MaterialModifier {
    Api26Material.refreshModifiers();
    if (selected) {
      return Api26Material.navigationSelectedModifier;
    }
    return Api26Material.navigationModifier;
  }
}
