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


#import "Mactypes.h"

void alaw_compress(long lseg, short *linbuf, Byte *logbuf) ;
void alaw_expand(long lseg, Byte *logbuf, short *linbuf) ;
  
  
void ulaw_compress(long lseg, short *linbuf, Byte *logbuf) ;
void ulaw_expand(long lseg, Byte *logbuf, short *linbuf) ;