import { createVuetify } from 'vuetify'
import defaults from './defaults'
import { icons } from './icons'
import theme from './theme'
import { aliases, mdi } from 'vuetify/iconsets/mdi'
import '@mdi/font/css/materialdesignicons.css' // Ensure you are using css-loader

// Styles
import '@core/scss/libs/vuetify/index.scss'
import 'vuetify/styles'
export default createVuetify({
  defaults,
  theme,
  icons: {
    defaultSet: 'mdi', // This is already the default value - only for display purposes
  },
})
