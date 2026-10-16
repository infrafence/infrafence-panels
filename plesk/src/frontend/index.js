// Copyright 2026 InfraFence. Licensed under the Business Source License 1.1.

import { createElement, createRoot } from '@plesk/ui-library';
import App from './App';
import { setMessages } from './i18n';
import { setApiUrl } from './api';

export default params => {
    setMessages(params.messages, params.locale);
    setApiUrl(params.apiUrl);
    createRoot(document.getElementById(params.mountId)).render(<App {...params} />);
};
