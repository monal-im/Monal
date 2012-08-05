/*                                                 Version 3.01 - 31.Jan.2000 
============================================================================= 

                          U    U   GGG    SSS  TTTTT 
                          U    U  G      S       T 
                          U    U  G  GG   SSS    T 
                          U    U  G   G      S   T 
                           UUUU    GGG    SSS    T 

                   ======================================== 
                    ITU-T - USER'S GROUP ON SOFTWARE TOOLS 
                   ======================================== 


       ============================================================= 
       COPYRIGHT NOTE: This source code, and all of its derivations, 
       is subject to the "ITU-T General Public License". Please have 
       it  read  in    the  distribution  disk,   or  in  the  ITU-T 
       Recommendation G.191 on "SOFTWARE TOOLS FOR SPEECH AND  AUDIO  
       CODING STANDARDS". 
       ============================================================= 


MODULE: G711.C, G.711 ENCODING/DECODING FUNCTIONS 

ORIGINAL BY: 

     Simao Ferraz de Campos Neto          Rudolf Hofmann 
     CPqD/Telebras                        PHILIPS KOMMUNIKATIONS INDUSTRIE AG 
     DDS/Pr.11                            Kommunikationssysteme 
     Rd. Mogi Mirim-Campinas Km.118       Thurn-und-Taxis-Strasse 14 
     13.085 - Campinas - SP (Brazil)      D-8500 Nuernberg 10 (Germany) 

     Phone : +55-192-39-6396              Phone : +49 911 526-2603 
     FAX   : +55-192-53-4754              FAX   : +49 911 526-3385 
     EMail : tdsimao@venus.cpqd.ansp.br   EMail : HF@PKINBG.UUCP 


FUNCTIONS: 

alaw_compress: ... compands 1 vector of linear PCM samples to A-law; 
                   uses 13 Most Sig.Bits (MSBs) from input and 8 Least 
                   Sig. Bits (LSBs) on output. 

alaw_expand: ..... expands 1 vector of A-law samples to linear PCM; 
                   use 8 Least Sig. Bits (LSBs) from input and 
                   13 Most Sig.Bits (MSBs) on output. 

ulaw_compress: ... compands 1 vector of linear PCM samples to u-law; 
                   uses 14 Most Sig.Bits (MSBs) from input and 8 Least 
                   Sig. Bits (LSBs) on output. 

ulaw_expand: ..... expands 1 vector of u-law samples to linear PCM 
                   use 8 Least Sig. Bits (LSBs) from input and 
                   14 Most Sig.Bits (MSBs) on output. 

PROTOTYPES: in g711.h 

HISTORY: 
Apr/91       1.0   First version of the G711 module 
10/Dec/1991  2.0   Break-up in individual functions for A,u law; 
                   correction of bug in compression routines (use of 1 
                   and 2 complement); Demo program inside module. 
08/Feb/1992  3.0   Demo as separate file; 
31/Jan/2000  3.01  Updated documentation text; no change in functions  
                   <simao.campos@labs.comsat.com> 
13jan2005          Byte for compressed data 
============================================================================= 
*/  
  
/* 
 *  .......... I N C L U D E S .......... 
 */  
  
/* Global prototype functions */  

  
/* 
 *  .......... F U N C T I O N S .......... 
 */  
  
/* ................... Begin of alaw_compress() ..................... */  
/* 
  ========================================================================== 

   FUNCTION NAME: alaw_compress 

   DESCRIPTION: ALaw encoding rule according ITU-T Rec. G.711. 

   PROTOTYPE: void alaw_compress(long lseg, short *linbuf, short *logbuf) 

   PARAMETERS: 
     lseg:  (In)  number of samples 
     linbuf:    (In)  buffer with linear samples (only 12 MSBits are taken 
                      into account) 
     logbuf:    (Out) buffer with compressed samples (8 bit right justified, 
                      without sign extension) 

   RETURN VALUE: none. 

   HISTORY: 
   10.Dec.91    1.0 Separated A-law compression function 

  ========================================================================== 
*/  
void alaw_compress(long lseg, short *linbuf, Byte *logbuf) ;
  
/* ................... End of alaw_compress() ..................... */  
  
  
/* ................... Begin of alaw_expand() ..................... */  
/* 
  ========================================================================== 

   FUNCTION NAME: alaw_expand 

   DESCRIPTION: ALaw decoding rule according ITU-T Rec. G.711. 

   PROTOTYPE: void alaw_expand(long lseg, short *logbuf, short *linbuf) 

   PARAMETERS: 
     lseg:  (In)  number of samples 
     logbuf:    (In)  buffer with compressed samples (8 bit right justified, 
                      without sign extension) 
     linbuf:    (Out) buffer with linear samples (13 bits left justified) 

   RETURN VALUE: none. 

   HISTORY: 
   10.Dec.91    1.0 Separated A-law expansion function 

  ============================================================================ 
*/  
void alaw_expand(long lseg, Byte *logbuf, short *linbuf) ;
  
/* ................... End of alaw_expand() ..................... */  
  
  
/* ................... Begin of ulaw_compress() ..................... */  
/* 
  ========================================================================== 

   FUNCTION NAME: ulaw_compress 

   DESCRIPTION: Mu law encoding rule according ITU-T Rec. G.711. 

   PROTOTYPE: void ulaw_compress(long lseg, short *linbuf, short *logbuf) 

   PARAMETERS: 
     lseg:  (In)  number of samples 
     linbuf:    (In)  buffer with linear samples (only 12 MSBits are taken 
                      into account) 
     logbuf:    (Out) buffer with compressed samples (8 bit right justified, 
                      without sign extension) 

   RETURN VALUE: none. 

   HISTORY: 
   10.Dec.91    1.0 Separated mu-law compression function 

  ========================================================================== 
*/  
void ulaw_compress(long lseg, short *linbuf, Byte *logbuf) ;
 
  
/* ................... End of ulaw_compress() ..................... */  
  
  
  
/* ................... Begin of ulaw_expand() ..................... */  
/* 
  ========================================================================== 

   FUNCTION NAME: ulaw_expand 

   DESCRIPTION: Mu law decoding rule according ITU-T Rec. G.711. 

   PROTOTYPE: void ulaw_expand(long lseg, short *logbuf, short *linbuf) 

   PARAMETERS: 
     lseg:  (In)  number of samples 
     logbuf:    (In)  buffer with compressed samples (8 bit right justified, 
                      without sign extension) 
     linbuf:    (Out) buffer with linear samples (14 bits left justified) 

   RETURN VALUE: none. 

   HISTORY: 
   10.Dec.91    1.0 Separated mu law expansion function 

  ============================================================================ 
*/  
  
void ulaw_expand(long lseg, Byte *logbuf, short *linbuf) ;
  
/* ................... End of ulaw_expand() ..................... */