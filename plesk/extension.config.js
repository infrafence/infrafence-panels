// Build settings for plesk-ext-sdk. The SDK supplies the Babel and webpack setup, and the
// Plesk UI library and React are not bundled: Plesk provides them at runtime (AMD module
// "plesk-ui-library"), so the screens always match the panel version and theme.
const path = require('path');

module.exports = {
    routes: [],
    webpack: config => {
        config.entry = path.resolve(__dirname, 'src/frontend/index.js');
        // The page is rendered by plib/controllers/IndexController.php (administrator only),
        // not by the generated htdocs/index.php.
        config.plugins = config.plugins.filter(p => p.constructor.name !== 'HtmlWebpackPlugin');
        config.devtool = false;
        return config;
    },
};
