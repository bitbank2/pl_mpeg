//
// Example MPEG-1 player for Arduino
// based on the pl_mpeg code
// With additional optimizations specifically for the ESP32-S3 SIMD instructions
// Written by Larry Bank (bitbank@pobox.com), January 19, 2025
//
#include <bb_spi_lcd.h> // https://github.com/bitbank2/bb_spi_lcd
// This macro must be defined for the .H file definitions to be used
#define PL_MPEG_IMPLEMENTATION
#include "../pl_mpeg.h"
#include "simpsons.h" // 320x240 MPEG-1 video w/audio of early Simpsons
BB_SPI_LCD lcd;
// I2S connections for the JC4827W543
#define PIN_STD_BCLK    GPIO_NUM_42     // I2S bit clock io number
#define PIN_STD_WS      GPIO_NUM_2      // I2S word select io number
#define PIN_STD_DOUT    GPIO_NUM_41     // I2S data out io number
#define PIN_STD_DIN     I2S_GPIO_UNUSED     // I2S data in io number
#include "driver/i2s_std.h" 
static i2s_chan_handle_t                tx_chan;        // I2S tx channel handler
int16_t i16Samples[1200];
plm_t *plm;
int iWidth, iHeight, iFrame;
#ifdef ARDUINO_ESP32S3_DEV
int16_t i16_Consts[8] = {0x80, 113, 90, 22, 46, 1,32,2048};
extern "C" {
  void s3_simd_ycbcr(uint8_t *pY, uint8_t *pCB, uint8_t *pCR, uint16_t *pOut, int16_t *pConsts, uint8_t ucPixelType);
}
#endif

void i2sInit(int iSampleRate)
{
    i2s_chan_config_t tx_chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_AUTO, I2S_ROLE_MASTER);
    ESP_ERROR_CHECK(i2s_new_channel(&tx_chan_cfg, &tx_chan, NULL));

    i2s_std_config_t tx_std_cfg = {
        .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(iSampleRate),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = I2S_GPIO_UNUSED,    // some codecs may require mclk signal, this example doesn't need it
            .bclk = PIN_STD_BCLK,
            .ws   = PIN_STD_WS,
            .dout = PIN_STD_DOUT,
            .din  = PIN_STD_DIN,
            .invert_flags = {
                .mclk_inv = false,
                .bclk_inv = false,
                .ws_inv   = false,
            },
        },
    };
    ESP_ERROR_CHECK(i2s_channel_init_std_mode(tx_chan, &tx_std_cfg));
    /* Before write data, start the tx channel first */
} /* i2sInit() */

void my_video_callback(plm_t *plm, plm_frame_t *frame, void *user) {
    int32_t x, y;
    uint16_t *d;
    uint8_t *pY, *pCb, *pCr;
    int iY1, iY2, iCb, iCr;
    int iOffX = (lcd.width() - iWidth)/2;
    int iOffY = (lcd.height() - iHeight)/2;
    uint16_t *pOut;
    static int iBufferToggle = 0;

    pOut = (uint16_t *)lcd.getDMABuffer();
    x = (intptr_t)pOut;
    x = (x + 15) & 0xfffffff0; // make sure it's 16-byte aligned otherwise the SIMD code will misbehave
    pOut = (uint16_t *)x;
    pOut += ((iBufferToggle & 1) * iWidth * 2); // don't clobber older pixels that are still being transmitted
    lcd.setAddrWindow(iOffX, iOffY, iWidth, iHeight);
    iBufferToggle++;
    for (y=0; y<iHeight; y+=2) { // work in pairs of lines
      d = pOut;
      pY = &frame->y.data[(y * iWidth)];
      pCb = &frame->cb.data[(y * iWidth/4)];
      pCr = &frame->cr.data[(y * iWidth/4)];
      for (x=0; x<iWidth; x+=16) {
        s3_simd_ycbcr(pY, pCb, pCr, &d[iWidth], i16_Consts, 1); // need to swap even/odd lines?
        s3_simd_ycbcr(&pY[iWidth], pCb, pCr, d, i16_Consts, 1);
        d += 16; // 16 RGB565 pixels done
        pCb += 8;
        pCr += 8;
        pY += 16;
      } // for x
      lcd.pushPixels(pOut, iWidth*2, DRAW_TO_LCD | DRAW_WITH_DMA); // send a row at a time to the display
    } // for y
    iFrame++;
} /* my_video_callback() */

void i2s_play_float(float *samples, uint16_t len)
{
  int i;
  for (i=0; i<len; i++) {                 
      i16Samples[i] = (int16_t)(samples[i*2] * 16384.0f); // 0.5 gain
  }
  size_t bytes_written;
  i2s_channel_write(tx_chan, i16Samples, len*2, &bytes_written, 100);
} /* i2s_play_float() */

// This function gets called for each decoded audio frame
void my_audio_callback(plm_t *plm, plm_samples_t *frame, void *user) {
  i2s_play_float(frame->interleaved, frame->count);
} /* my_audio_callback() */

void setup()
{
  Serial.begin(115200);
  lcd.begin(DISPLAY_CYD_543); // JC4827W543 480x270 QSPI ESP32-S3 "cheap yellow display"
  lcd.fillScreen(TFT_BLACK);
  lcd.setTextColor(TFT_GREEN);
  lcd.setFont(FONT_12x16);
  lcd.setCursor(132,0); // center
  lcd.println("MPEG-1 Player Test");
} /* setup() */

void loop() 
{
  long l, lStart;
   plm = plm_create_with_memory((uint8_t *)simpsons, (uint32_t)sizeof(simpsons), 0); // create the pl_mpeg object
   if (!plm) {
      lcd.setTextColor(TFT_RED);
      lcd.println("Error opening MPEG-1 file!");
      while (1) {}; // stop
   }
   iWidth = plm_get_width(plm);
   iHeight = plm_get_height(plm);
   int samplerate = plm_get_samplerate(plm);
   float framerate = plm_get_framerate(plm);
   double frame_time = 1.0 / framerate;
   long delay = (long)(1000000.0f / framerate);
   // our callback functions
   plm_set_video_decode_callback(plm, my_video_callback, NULL);
   plm_set_audio_decode_callback(plm, my_audio_callback, NULL);
   i2sInit(samplerate);
   i2s_channel_enable(tx_chan); // start the audio channel
   // Play the video
   lStart = millis();
   do {
      l = micros();
      plm_decode(plm, frame_time);
      l = micros() - l; // time in us to decode this frame
      if (l < delay) { // extra time, try to sync
        delayMicroseconds(delay - l);
      }
   } while (!plm_has_ended(plm));
   lStart = millis() - lStart;
   lcd.setCursor(0, lcd.height()-16);
   lcd.printf("Avg = %d fps, rated = %d fps", (int)((1000 * iFrame)/lStart), (int)(framerate+0.1f));
   plm_destroy(plm);
   i2s_channel_disable(tx_chan); // turn off audio

   while (1) {}; // one play is enough
} /* loop() */