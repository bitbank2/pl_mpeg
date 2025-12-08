//
// Performance test program for pl_mpeg
// written by Larry Bank
// This program will measure the decoding time of video alone
// and video plus audio
//
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#define PL_MPEG_IMPLEMENTATION
#include <pl_mpeg.h>

//
// Return the current time in milliseconds
//
int64_t millis(void)
{
int64_t iTime; 
struct timespec res;

    clock_gettime(CLOCK_MONOTONIC, &res);
    iTime = 1000*res.tv_sec + res.tv_nsec/1000000;

    return iTime;
} /* millis() */

int main(int argc, char *argv[])
{
FILE *infile;
int iFrame, iSize;
uint8_t *pVideo;
plm_t *plm;
int64_t iTime;

    if (argc != 2) {
        printf("Usage: perf <testfile.mpeg>\n");
        return -1;
    }
    // To rule out file I/O latency, read the whole file into memory
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

    // Test video decoding only
    plm = plm_create_with_memory(pVideo, iSize, 0);
    if (!plm) {
        printf("Error creating pl_mpeg structure.\n");
        free(pVideo);
        return -1;
    }    
    iTime = millis();
    iFrame = 0;
    // Decode all frames
    do {
        iFrame++;
        plm_decode_video(plm);
    } while (!plm_has_ended(plm));
    plm_destroy(plm);
    iTime = (millis() - iTime);
    printf("Video only: %d frames in %dms\n", iFrame, (int)iTime);
    // Test video and audio performance
    // Test video decoding only
    plm = plm_create_with_memory(pVideo, iSize, 0);
    if (!plm) {
        printf("Error creating pl_mpeg structure.\n");
        free(pVideo);
        return -1;
    }
    iTime = millis();
    iFrame = 0;
    // Decode all frames
    do {
        iFrame++;
        plm_decode_video(plm);
        plm_decode_audio(plm);
    } while (!plm_has_ended(plm));
    plm_destroy(plm);
    iTime = (millis() - iTime);
    printf("Video+Audio: %d frames in %dms\n", iFrame, (int)iTime);
    free(pVideo);
    return 0;
} /* main() */

