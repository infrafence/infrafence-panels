// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import {
    createElement,
    Button,
    Heading,
    Panel,
    Paragraph,
} from '@plesk/ui-library';
import { t } from '../i18n';

const NotInstalled = ({ addServerUrl, onCheckAgain, checking }) => (
    <Panel className="infrafence__not-installed">
        <Heading level={3}>{t('notInstalled.title')}</Heading>
        <Paragraph>{t('notInstalled.text')}</Paragraph>
        <Paragraph>{t('notInstalled.step')}</Paragraph>
        <div className="infrafence__actions">
            <Button component="a" href={addServerUrl} target="_blank" rel="noopener noreferrer" intent="primary" icon="arrow-diagonal-out">
                {t('notInstalled.addServer')}
            </Button>
            <Button icon="refresh" state={checking ? 'loading' : undefined} onClick={onCheckAgain}>
                {t('notInstalled.checkAgain')}
            </Button>
        </div>
    </Panel>
);

export default NotInstalled;
