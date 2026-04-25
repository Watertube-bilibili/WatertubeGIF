import BackupExtensionAbility, { BundleVersion } from '@ohos.application.BackupExtensionAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
  }
}
