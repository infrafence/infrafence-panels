// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    Button,
    Heading,
    Hint,
    Panel,
    Paragraph,
    copyToClipboard,
} from '@plesk/ui-library';
import { t } from '../i18n';
import { toast } from '../common';

const NotInstalled = ({ installCommand, dashboardUrl, onCheckAgain, checking }) => (
    <Panel className="infrafence__not-installed">
        <Heading level={3}>{t('notInstalled.title')}</Heading>
        <Paragraph>{t('notInstalled.text')}</Paragraph>
        <Paragraph>{t('notInstalled.step')}</Paragraph>
        <div className="infrafence__command">
            <code>{installCommand}</code>
            <Button
                ghost
                icon="copy"
                tooltip={t('notInstalled.copy')}
                onClick={() => {
                    copyToClipboard(installCommand);
                    toast('success', t('notInstalled.copied'));
                }}
            />
        </div>
        <Hint>{t('notInstalled.hint')}</Hint>
        <div className="infrafence__actions">
            <Button intent="primary" icon="refresh" state={checking ? 'loading' : undefined} onClick={onCheckAgain}>
                {t('notInstalled.checkAgain')}
            </Button>
            <Button component="a" href={dashboardUrl} target="_blank" rel="noopener noreferrer" icon="arrow-diagonal-out">
                {t('notInstalled.openDashboard')}
            </Button>
        </div>
    </Panel>
);

export default NotInstalled;
