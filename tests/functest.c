//
// Functional test program for pl_mpeg
// written by Larry Bank
// This program will calculate and display a checksum value for each
// frame decoded.
//
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define PL_MPEG_IMPLEMENTATION
#include <pl_mpeg.h>
uint32_t crc32_table[256];
uint32_t u32crc_y, u32crc_cr, u32crc_cb, u32sum;

uint32_t Reflect(uint32_t ref, char ch) 
{// Used only by Init_CRC32_Table(). 
uint32_t value = 0;
int i;

      // Swap bit 0 for bit 7 
      // bit 1 for bit 6, etc. 
      for(i=1; i < (ch + 1); i++) 
      { 
            if(ref & 1) 
                  value |= 1 << (ch - i); 
            ref >>= 1; 
      } 
      return value; 
}  /* Reflect() */

void Init_CRC32_Table(void)
{
int i, j;

      // This is the official polynomial used by CRC-32 
      // in PKZip, WinZip and Ethernet. 
      uint32_t ulPolynomial = 0x04c11db7; 
      memset(crc32_table,0,256*sizeof(int));

      // 256 values representing ASCII character codes. 
      for(i = 0; i <= 0xFF; i++) { 
            crc32_table[i]=Reflect(i, 8) << 24; 
            for (j = 0; j < 8; j++) { 
                  crc32_table[i] = (crc32_table[i] << 1) ^ (crc32_table[i] & (1 << 31) ? ulPolynomial : 0); 
            }
            crc32_table[i] = Reflect(crc32_table[i], 32); 
      } 
}  /* Init_CRC32_Table() */

uint32_t CalcCRC(uint8_t *pData, int iLen)
{
int i;
uint32_t ulCRC;

   ulCRC = 0;
   for (i=0; i<iLen; i++) {
       ulCRC = (ulCRC >> 8) ^ crc32_table[(ulCRC & 0xFF) ^ *pData++]; 
   }
   return ulCRC;

} /* CalcCRC() */

int main(int argc, char *argv[])
{
FILE *infile;
int iFrame, iSize;
uint8_t *pVideo;
plm_t *plm;
plm_frame_t *frame;

    if (argc != 2) {
        printf("Usage: test <testfile.mpeg>\n");
        return -1;
    }
    Init_CRC32_Table();
    // To simplify re-use of the input file, read it into memory
    infile = fopen(argv[1], "r+b");
    if (infile == NULL) {
        printf("Error opening input file %s\n", argv[1]);
        return -1;
    }
    // Read the file into RAM
    fseek(infile, 0, SEEK_END);
    iSize = (int)ftell(infile);
    fseek(infile, 0, SEEK_SET);
    pVideo = (uint8_t *)malloc(iSize);
    fread(pVideo, 1, iSize, infile);
    fclose(infile);

    // Decode each frame and print the CRC32 of the pixel data
    plm = plm_create_with_memory(pVideo, iSize, 0);
    if (!plm) {
        printf("Error creating pl_mpeg structure.\n");
        free(pVideo);
        return -1;
    }
    // Decode all frames
    iFrame = 0;
    u32sum = 0;
    do {
        iFrame++;
        frame = plm_decode_video(plm);
        if (frame) {
            // Calculate the CRC32 for the frame (pixel) data
            iSize = frame->width * frame->height;
            u32crc_y = CalcCRC(frame->y.data, iSize);
            u32crc_cr = CalcCRC(frame->cr.data, iSize/4);
            u32crc_cb = CalcCRC(frame->cb.data, iSize/4);
            printf("Frame %d CRC: y:0x%08x cr:0x%08x cb:0x%08x\n", iFrame, u32crc_y, u32crc_cr, u32crc_cb);
            u32sum += u32crc_y;          
        }
    } while (!plm_has_ended(plm));
    printf("crc32 sum of entire video: 0x%08x\n", u32sum);
    plm_destroy(plm);
    free(pVideo);
    return 0;
} /* main() */

