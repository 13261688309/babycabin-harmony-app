import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { controller } from '../model/Controller';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index');
  }
  onBackground(): void { controller.suspend(); }
  onDestroy(): void { controller.suspend(); }
}
