	; IntyBASIC compiler v1.2.5 Feb/16/2016
        ;
        ; Prologue for IntyBASIC programs
        ; by Oscar Toledo G.  http://nanochess.org/
        ;
        ; Revision: Jan/30/2014. Spacing adjustment and more comments.
        ; Revision: Apr/01/2014. It now sets the starting screen pos. for PRINT
	    ; Revision: Aug/26/2014. Added PAL detection code.
	    ; Revision: Dec/12/2014. Added optimized constant multiplication routines
	    ;                        by James Pujals.
	    ; Revision: Jan/25/2015. Added marker for automatic title replacement.
	    ;                        (option --title of IntyBASIC)
	    ; Revision: Aug/06/2015. Turns off ECS sound. Seed random generator using
	    ;                        trash in 16-bit RAM. Solved bugs and optimized
	    ;                        macro for constant multiplication.
        ; Revision: Jan/12/2016. Solved bug in PAL detection.
	    ;

        ROMW 16
        ORG $5000

        ; This macro will 'eat' SRCFILE directives if the assembler doesn't support the directive.
        IF ( DEFINED __FEATURE.SRCFILE ) = 0
            MACRO SRCFILE x, y
            ; macro must be non-empty, but a comment works fine.
            ENDM
        ENDI

        ;
        ; ROM header
        ;
        BIDECLE _ZERO           ; MOB picture base
        BIDECLE _ZERO           ; Process table
        BIDECLE _MAIN           ; Program start
        BIDECLE _ZERO           ; Background base image
        BIDECLE _ONES           ; GRAM
        BIDECLE _TITLE          ; Cartridge title and date
        DECLE   $03C0           ; No ECS title, jump to code after title,
                                ; ... no clicks
                                
_ZERO:  DECLE   $0000           ; Border control
        DECLE   $0000           ; 0 = color stack, 1 = f/b mode
        
_ONES:  DECLE   $0001, $0001    ; Initial color stack 0 and 1: Blue
        DECLE   $0001, $0001    ; Initial color stack 2 and 3: Blue
        DECLE   $0001           ; Initial border color: Blue

C_WHT:  EQU $0007

CLRSCR: MVII #$200,R4           ; Used also for CLS
        MVII #$F0,R1
FILLZERO:
        CLRR R0
MEMSET:
        MVO@ R0,R4
        DECR R1
        BNE MEMSET
        JR R5

        ;
        ; Title, Intellivision EXEC will jump over it and start
        ; execution directly in _MAIN
        ;
	; Note mark is for automatic replacement by IntyBASIC
_TITLE:
	BYTE 116,'IntyMusic',0
        
        ;
        ; Main program
        ;
_MAIN:
        DIS
        MVII #STACK,R6

_MAIN0:
        ;
        ; Clean memory
        ;
        MVII #$00e,R1           ; 14 of sound (ECS)
        MVII #$0f0,R4           ; ECS PSG
        CALL FILLZERO
        MVII #$0fe,R1           ; 240 words of 8 bits plus 14 of sound
        MVII #$100,R4           ; 8-bit scratch RAM
        CALL FILLZERO

	; Seed random generator using 16 bit RAM (not cleared by EXEC)
	CLRR R0
	MVII #$02F0,R4
	MVII #$0110/4,R1        ; Includes phantom memory for extra randomness
_MAIN4:                         ; This loop is courtesy of GroovyBee
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	DECR R1
	BNE _MAIN4
	MVO R0,_rand

        MVII #$058,R1           ; 88 words of 16 bits
        MVII #$308,R4           ; 16-bit scratch RAM
        CALL FILLZERO

        CALL CLRSCR             ; Clean up screen

        MVII #_pal1_vector,R0 ; Points to interrupt vector
        MVO R0,ISRVEC
        SWAP R0
        MVO R0,ISRVEC+1

        EIS

_MAIN1:	MVI _ntsc,R0
	CMPI #3,R0
	BNE _MAIN1
	CLRR R2
_MAIN2:	INCR R2
	MVI _ntsc,R0
	CMPI #4,R0
	BNE _MAIN2

        ; 596 for PAL in jzintv
        ; 444 for NTSC in jzintv
        CMPI #520,R2
        MVII #1,R0
        BLE _MAIN3
        CLRR R0
_MAIN3: MVO R0,_ntsc

        CALL _wait
	CALL _init_music
        MVII #1,R0
        MVO R0,_mode_select
        MVII #$038,R0
        MVO R0,$01F8            ; Configures sound
        MVO R0,$00F8            ; Configures sound (ECS)
        CALL _wait

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- James Pujals (DZ-Jay), 2014                              *;
;* ======================================================================== *;

; Modified by Oscar Toledo G. (nanochess), Aug/06/2015
; * Tested all multiplications with automated test.
; * Accelerated multiplication by 7,14,15,28,31,60,62,63,112,120,124
; * Solved bug in multiplication by 23,39,46,47,55,71,78,79,87,92,93,94,95,103,110,111,119
; * Improved sequence of instructions to be more interruptible.

;; ======================================================================== ;;
;;  MULT reg, tmp, const                                                    ;;
;;  Multiplies "reg" by constant "const" and using "tmp" for temporary      ;;
;;  calculations.  The result is placed in "reg."  The multiplication is    ;;
;;  performed by an optimal combination of shifts, additions, and           ;;
;;  subtractions.                                                           ;;
;;                                                                          ;;
;;  NOTE:   The resulting contents of the "tmp" are undefined.              ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      reg         A register containing the multiplicand.                 ;;
;;      tmp         A register for temporary calculations.                  ;;
;;      const       The constant multiplier.                                ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      reg         Output value.                                           ;;
;;      tmp         Trashed.                                                ;;
;;      .ERR.Failed True if operation failed.                               ;;
;; ======================================================================== ;;
MACRO   MULT reg, tmp, const
;
    LISTING "code"

_mul.const      QSET    %const%
_mul.done       QSET    0

        IF (%const% > $7F)
_mul.const      QSET    (_mul.const SHR 1)
                SLL     %reg%,  1
        ENDI

        ; Multiply by $00 (0)
        IF (_mul.const = $00)
_mul.done       QSET    -1
                CLRR    %reg%
        ENDI

        ; Multiply by $01 (1)
        IF (_mul.const = $01)
_mul.done       QSET    -1
                ; Nothing to do
        ENDI

        ; Multiply by $02 (2)
        IF (_mul.const = $02)
_mul.done       QSET    -1
                SLL     %reg%,  1
        ENDI

        ; Multiply by $03 (3)
        IF (_mul.const = $03)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $04 (4)
        IF (_mul.const = $04)
_mul.done       QSET    -1
                SLL     %reg%,  2
        ENDI

        ; Multiply by $05 (5)
        IF (_mul.const = $05)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $06 (6)
        IF (_mul.const = $06)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $07 (7)
        IF (_mul.const = $07)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $08 (8)
        IF (_mul.const = $08)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
        ENDI

        ; Multiply by $09 (9)
        IF (_mul.const = $09)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0A (10)
        IF (_mul.const = $0A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0B (11)
        IF (_mul.const = $0B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0C (12)
        IF (_mul.const = $0C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0D (13)
        IF (_mul.const = $0D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0E (14)
        IF (_mul.const = $0E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0F (15)
        IF (_mul.const = $0F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $10 (16)
        IF (_mul.const = $10)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $11 (17)
        IF (_mul.const = $11)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $12 (18)
        IF (_mul.const = $12)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $13 (19)
        IF (_mul.const = $13)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $14 (20)
        IF (_mul.const = $14)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $15 (21)
        IF (_mul.const = $15)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $16 (22)
        IF (_mul.const = $16)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $17 (23)
        IF (_mul.const = $17)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $18 (24)
        IF (_mul.const = $18)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $19 (25)
        IF (_mul.const = $19)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1A (26)
        IF (_mul.const = $1A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1B (27)
        IF (_mul.const = $1B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1C (28)
        IF (_mul.const = $1C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1D (29)
        IF (_mul.const = $1D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1E (30)
        IF (_mul.const = $1E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1F (31)
        IF (_mul.const = $1F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $20 (32)
        IF (_mul.const = $20)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
        ENDI

        ; Multiply by $21 (33)
        IF (_mul.const = $21)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $22 (34)
        IF (_mul.const = $22)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $23 (35)
        IF (_mul.const = $23)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $24 (36)
        IF (_mul.const = $24)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $25 (37)
        IF (_mul.const = $25)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $26 (38)
        IF (_mul.const = $26)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $27 (39)
        IF (_mul.const = $27)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $28 (40)
        IF (_mul.const = $28)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $29 (41)
        IF (_mul.const = $29)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2A (42)
        IF (_mul.const = $2A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2B (43)
        IF (_mul.const = $2B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2C (44)
        IF (_mul.const = $2C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2D (45)
        IF (_mul.const = $2D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2E (46)
        IF (_mul.const = $2E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $2F (47)
        IF (_mul.const = $2F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $30 (48)
        IF (_mul.const = $30)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $31 (49)
        IF (_mul.const = $31)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $32 (50)
        IF (_mul.const = $32)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $33 (51)
        IF (_mul.const = $33)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $34 (52)
        IF (_mul.const = $34)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $35 (53)
        IF (_mul.const = $35)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $36 (54)
        IF (_mul.const = $36)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $37 (55)
        IF (_mul.const = $37)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
		SLL	%reg%,	1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $38 (56)
        IF (_mul.const = $38)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $39 (57)
        IF (_mul.const = $39)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3A (58)
        IF (_mul.const = $3A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3B (59)
        IF (_mul.const = $3B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3C (60)
        IF (_mul.const = $3C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3D (61)
        IF (_mul.const = $3D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3E (62)
        IF (_mul.const = $3E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3F (63)
        IF (_mul.const = $3F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $40 (64)
        IF (_mul.const = $40)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $41 (65)
        IF (_mul.const = $41)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $42 (66)
        IF (_mul.const = $42)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $43 (67)
        IF (_mul.const = $43)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $44 (68)
        IF (_mul.const = $44)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $45 (69)
        IF (_mul.const = $45)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $46 (70)
        IF (_mul.const = $46)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $47 (71)
        IF (_mul.const = $47)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $48 (72)
        IF (_mul.const = $48)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $49 (73)
        IF (_mul.const = $49)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4A (74)
        IF (_mul.const = $4A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4B (75)
        IF (_mul.const = $4B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4C (76)
        IF (_mul.const = $4C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4D (77)
        IF (_mul.const = $4D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4E (78)
        IF (_mul.const = $4E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $4F (79)
        IF (_mul.const = $4F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $50 (80)
        IF (_mul.const = $50)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $51 (81)
        IF (_mul.const = $51)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $52 (82)
        IF (_mul.const = $52)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $53 (83)
        IF (_mul.const = $53)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $54 (84)
        IF (_mul.const = $54)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $55 (85)
        IF (_mul.const = $55)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $56 (86)
        IF (_mul.const = $56)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $57 (87)
        IF (_mul.const = $57)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR    %reg%,	%tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $58 (88)
        IF (_mul.const = $58)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $59 (89)
        IF (_mul.const = $59)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5A (90)
        IF (_mul.const = $5A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5B (91)
        IF (_mul.const = $5B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5C (92)
        IF (_mul.const = $5C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5D (93)
        IF (_mul.const = $5D)
_mul.done       QSET    -1
		MOVR	%reg%,	%tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5E (94)
        IF (_mul.const = $5E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5F (95)
        IF (_mul.const = $5F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                ADDR	%reg%,	%reg%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $60 (96)
        IF (_mul.const = $60)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $61 (97)
        IF (_mul.const = $61)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $62 (98)
        IF (_mul.const = $62)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $63 (99)
        IF (_mul.const = $63)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $64 (100)
        IF (_mul.const = $64)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $65 (101)
        IF (_mul.const = $65)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $66 (102)
        IF (_mul.const = $66)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $67 (103)
        IF (_mul.const = $67)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $68 (104)
        IF (_mul.const = $68)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $69 (105)
        IF (_mul.const = $69)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6A (106)
        IF (_mul.const = $6A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6B (107)
        IF (_mul.const = $6B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6C (108)
        IF (_mul.const = $6C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6D (109)
        IF (_mul.const = $6D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6E (110)
        IF (_mul.const = $6E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $6F (111)
        IF (_mul.const = $6F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $70 (112)
        IF (_mul.const = $70)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $71 (113)
        IF (_mul.const = $71)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $72 (114)
        IF (_mul.const = $72)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $73 (115)
        IF (_mul.const = $73)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $74 (116)
        IF (_mul.const = $74)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $75 (117)
        IF (_mul.const = $75)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $76 (118)
        IF (_mul.const = $76)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $77 (119)
        IF (_mul.const = $77)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $78 (120)
        IF (_mul.const = $78)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $79 (121)
        IF (_mul.const = $79)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7A (122)
        IF (_mul.const = $7A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7B (123)
        IF (_mul.const = $7B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7C (124)
        IF (_mul.const = $7C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7D (125)
        IF (_mul.const = $7D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7E (126)
        IF (_mul.const = $7E)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SWAP    %reg%,  1
                SLR     %reg%,  1
		ADDR    %tmp%,  %tmp%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7F (127)
        IF (_mul.const = $7F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SWAP    %reg%, 1
                SLR     %reg%, 1
                SUBR    %tmp%,  %reg%
        ENDI

        IF  (_mul.done = 0)
            ERR $("Invalid multiplication constant \'%const%\', must be between 0 and ", $#($7F), ".")
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  EOF: pm:mac:lang:mult                                                   ;;
;; ======================================================================== ;;

	;FILE IntyMusic.bas
	;[1] 'IntyMusic by Marco A. Marrero.  Started at 7-30-2016, version 8/10/2016
	SRCFILE "IntyMusic.bas",1
	;[2] 
	SRCFILE "IntyMusic.bas",2
	;[3] '----Required----
	SRCFILE "IntyMusic.bas",3
	;[4] INCLUDE "constants.bas"
	SRCFILE "IntyMusic.bas",4
	;FILE C:\Apps\Intellivision\bin\constants.bas
	;[1] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",1
	;[2] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",2
	;[3] REM Background information.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",3
	;[4] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",4
	;[5] CONST BACKTAB				= $0200		' Start of the background in RAM.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",5
	;[6] CONST BACKGROUND_ROWS		= 12		' Height of the background in cards.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",6
	;[7] CONST BACKGROUND_COLUMNS	= 20		' Width of the background in cards.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",7
	;[8] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",8
	;[9] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",9
	;[10] REM Background GRAM cards.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",10
	;[11] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",11
	;[12] CONST BG00 					= $0800
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",12
	;[13] CONST BG01 					= $0808
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",13
	;[14] CONST BG02 					= $0810
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",14
	;[15] CONST BG03 					= $0818
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",15
	;[16] CONST BG04 					= $0820
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",16
	;[17] CONST BG05 					= $0828
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",17
	;[18] CONST BG06 					= $0830
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",18
	;[19] CONST BG07 					= $0838
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",19
	;[20] CONST BG08 					= $0840
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",20
	;[21] CONST BG09 					= $0848
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",21
	;[22] CONST BG10 					= $0850
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",22
	;[23] CONST BG11 					= $0858
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",23
	;[24] CONST BG12 					= $0860
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",24
	;[25] CONST BG13 					= $0868
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",25
	;[26] CONST BG14 					= $0870
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",26
	;[27] CONST BG15 					= $0878
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",27
	;[28] CONST BG16 					= $0880
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",28
	;[29] CONST BG17 					= $0888
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",29
	;[30] CONST BG18 					= $0890
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",30
	;[31] CONST BG19 					= $0898
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",31
	;[32] CONST BG20 					= $08A0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",32
	;[33] CONST BG21 					= $08A8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",33
	;[34] CONST BG22 					= $08B0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",34
	;[35] CONST BG23 					= $08B8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",35
	;[36] CONST BG24 					= $08C0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",36
	;[37] CONST BG25 					= $08C8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",37
	;[38] CONST BG26 					= $08D0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",38
	;[39] CONST BG27 					= $08D8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",39
	;[40] CONST BG28 					= $08E0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",40
	;[41] CONST BG29 					= $08E8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",41
	;[42] CONST BG30 					= $08F0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",42
	;[43] CONST BG31 					= $08F8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",43
	;[44] CONST BG32 					= $0900
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",44
	;[45] CONST BG33 					= $0908
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",45
	;[46] CONST BG34 					= $0910
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",46
	;[47] CONST BG35 					= $0918
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",47
	;[48] CONST BG36 					= $0920
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",48
	;[49] CONST BG37 					= $0928
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",49
	;[50] CONST BG38 					= $0930
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",50
	;[51] CONST BG39 					= $0938
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",51
	;[52] CONST BG40 					= $0940
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",52
	;[53] CONST BG41 					= $0948
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",53
	;[54] CONST BG42 					= $0950
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",54
	;[55] CONST BG43 					= $0958
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",55
	;[56] CONST BG44 					= $0960
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",56
	;[57] CONST BG45 					= $0968
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",57
	;[58] CONST BG46 					= $0970
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",58
	;[59] CONST BG47 					= $0978
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",59
	;[60] CONST BG48 					= $0980
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",60
	;[61] CONST BG49 					= $0988
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",61
	;[62] CONST BG50 					= $0990
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",62
	;[63] CONST BG51 					= $0998
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",63
	;[64] CONST BG52 					= $09A0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",64
	;[65] CONST BG53 					= $09A8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",65
	;[66] CONST BG54 					= $09B0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",66
	;[67] CONST BG55 					= $09B8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",67
	;[68] CONST BG56 					= $09C0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",68
	;[69] CONST BG57 					= $09C8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",69
	;[70] CONST BG58 					= $09D0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",70
	;[71] CONST BG59 					= $09D8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",71
	;[72] CONST BG60 					= $09E0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",72
	;[73] CONST BG61 					= $09E8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",73
	;[74] CONST BG62 					= $09F0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",74
	;[75] CONST BG63 					= $09F8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",75
	;[76] 	
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",76
	;[77] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",77
	;[78] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",78
	;[79] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",79
	;[80] REM GRAM card index numbers.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",80
	;[81] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",81
	;[82] REM Note: For use with the "define" command.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",82
	;[83] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",83
	;[84] CONST DEF00 				= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",84
	;[85] CONST DEF01 				= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",85
	;[86] CONST DEF02 				= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",86
	;[87] CONST DEF03 				= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",87
	;[88] CONST DEF04 				= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",88
	;[89] CONST DEF05 				= $0005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",89
	;[90] CONST DEF06 				= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",90
	;[91] CONST DEF07 				= $0007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",91
	;[92] CONST DEF08 				= $0008
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",92
	;[93] CONST DEF09 				= $0009
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",93
	;[94] CONST DEF10 				= $000A
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",94
	;[95] CONST DEF11 				= $000B
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",95
	;[96] CONST DEF12 				= $000C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",96
	;[97] CONST DEF13 				= $000D
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",97
	;[98] CONST DEF14 				= $000E
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",98
	;[99] CONST DEF15 				= $000F
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",99
	;[100] CONST DEF16 				= $0010
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",100
	;[101] CONST DEF17 				= $0011
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",101
	;[102] CONST DEF18 				= $0012
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",102
	;[103] CONST DEF19 				= $0013
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",103
	;[104] CONST DEF20 				= $0014
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",104
	;[105] CONST DEF21 				= $0015
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",105
	;[106] CONST DEF22 				= $0016
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",106
	;[107] CONST DEF23 				= $0017
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",107
	;[108] CONST DEF24 				= $0018
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",108
	;[109] CONST DEF25 				= $0019
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",109
	;[110] CONST DEF26 				= $001A
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",110
	;[111] CONST DEF27 				= $001B
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",111
	;[112] CONST DEF28 				= $001C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",112
	;[113] CONST DEF29 				= $001D
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",113
	;[114] CONST DEF30 				= $001E
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",114
	;[115] CONST DEF31 				= $001F
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",115
	;[116] CONST DEF32 				= $0020
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",116
	;[117] CONST DEF33 				= $0021
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",117
	;[118] CONST DEF34 				= $0022
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",118
	;[119] CONST DEF35 				= $0023
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",119
	;[120] CONST DEF36 				= $0024
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",120
	;[121] CONST DEF37 				= $0025
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",121
	;[122] CONST DEF38 				= $0026
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",122
	;[123] CONST DEF39 				= $0027
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",123
	;[124] CONST DEF40 				= $0028
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",124
	;[125] CONST DEF41 				= $0029
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",125
	;[126] CONST DEF42 				= $002A
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",126
	;[127] CONST DEF43 				= $002B
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",127
	;[128] CONST DEF44 				= $002C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",128
	;[129] CONST DEF45 				= $002D
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",129
	;[130] CONST DEF46 				= $002E
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",130
	;[131] CONST DEF47 				= $002F
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",131
	;[132] CONST DEF48 				= $0030
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",132
	;[133] CONST DEF49 				= $0031
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",133
	;[134] CONST DEF50 				= $0032
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",134
	;[135] CONST DEF51 				= $0033
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",135
	;[136] CONST DEF52 				= $0034
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",136
	;[137] CONST DEF53 				= $0035
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",137
	;[138] CONST DEF54 				= $0036
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",138
	;[139] CONST DEF55 				= $0037
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",139
	;[140] CONST DEF56 				= $0038
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",140
	;[141] CONST DEF57 				= $0039
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",141
	;[142] CONST DEF58 				= $003A
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",142
	;[143] CONST DEF59 				= $003B
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",143
	;[144] CONST DEF60 				= $003C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",144
	;[145] CONST DEF61 				= $003D
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",145
	;[146] CONST DEF62 				= $003E
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",146
	;[147] CONST DEF63 				= $003F
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",147
	;[148] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",148
	;[149] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",149
	;[150] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",150
	;[151] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",151
	;[152] REM Screen modes.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",152
	;[153] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",153
	;[154] REM Note: For use with the "mode" command.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",154
	;[155] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",155
	;[156] CONST SCREEN_COLOR_STACK			= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",156
	;[157] CONST SCREEN_FOREGROUND_BACKGROUND	= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",157
	;[158] REM Abbreviated versions.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",158
	;[159] CONST SCREEN_CS						= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",159
	;[160] CONST SCREEN_FB						= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",160
	;[161] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",161
	;[162] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",162
	;[163] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",163
	;[164] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",164
	;[165] REM COLORS - Border.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",165
	;[166] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",166
	;[167] REM Notes:
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",167
	;[168] REM - For use with the commands "mode 0" and "mode 1".
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",168
	;[169] REM - For use with the "border" command.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",169
	;[170] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",170
	;[171] CONST BORDER_BLACK			= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",171
	;[172] CONST BORDER_BLUE			= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",172
	;[173] CONST BORDER_RED			= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",173
	;[174] CONST BORDER_TAN			= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",174
	;[175] CONST BORDER_DARKGREEN		= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",175
	;[176] CONST BORDER_GREEN			= $0005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",176
	;[177] CONST BORDER_YELLOW			= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",177
	;[178] CONST BORDER_WHITE			= $0007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",178
	;[179] CONST BORDER_GREY			= $0008
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",179
	;[180] CONST BORDER_CYAN			= $0009
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",180
	;[181] CONST BORDER_ORANGE			= $000A
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",181
	;[182] CONST BORDER_BROWN			= $000B
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",182
	;[183] CONST BORDER_PINK			= $000C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",183
	;[184] CONST BORDER_LIGHTBLUE		= $000D
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",184
	;[185] CONST BORDER_YELLOWGREEN	= $000E
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",185
	;[186] CONST BORDER_PURPLE			= $000F
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",186
	;[187] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",187
	;[188] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",188
	;[189] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",189
	;[190] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",190
	;[191] REM BORDER - Edge masks.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",191
	;[192] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",192
	;[193] REM Note: For use with the "border color, edge" command.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",193
	;[194] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",194
	;[195] CONST BORDER_HIDE_LEFT_EDGE		= $0001		' Hide the leftmost column of the background.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",195
	;[196] CONST BORDER_HIDE_TOP_EDGE		= $0002		' Hide the topmost row of the background.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",196
	;[197] CONST BORDER_HIDE_TOP_LEFT_EDGE	= $0003		' Hide both the topmost row and leftmost column of the background.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",197
	;[198] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",198
	;[199] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",199
	;[200] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",200
	;[201] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",201
	;[202] REM COLORS - Mode 0 (Color Stack).
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",202
	;[203] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",203
	;[204] REM Stack
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",204
	;[205] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",205
	;[206] REM Note: For use as the last 4 parameters used in the "mode 1" command.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",206
	;[207] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",207
	;[208] CONST STACK_BLACK			= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",208
	;[209] CONST STACK_BLUE			= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",209
	;[210] CONST STACK_RED				= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",210
	;[211] CONST STACK_TAN				= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",211
	;[212] CONST STACK_DARKGREEN		= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",212
	;[213] CONST STACK_GREEN			= $0005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",213
	;[214] CONST STACK_YELLOW			= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",214
	;[215] CONST STACK_WHITE			= $0007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",215
	;[216] CONST STACK_GREY			= $0008
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",216
	;[217] CONST STACK_CYAN			= $0009
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",217
	;[218] CONST STACK_ORANGE			= $000A
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",218
	;[219] CONST STACK_BROWN			= $000B
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",219
	;[220] CONST STACK_PINK			= $000C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",220
	;[221] CONST STACK_LIGHTBLUE		= $000D
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",221
	;[222] CONST STACK_YELLOWGREEN		= $000E
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",222
	;[223] CONST STACK_PURPLE			= $000F
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",223
	;[224] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",224
	;[225] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",225
	;[226] REM Foreground.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",226
	;[227] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",227
	;[228] REM Notes:
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",228
	;[229] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",229
	;[230] REM - Only one foreground colour permitted per background card.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",230
	;[231] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",231
	;[232] CONST CS_BLACK				= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",232
	;[233] CONST CS_BLUE				= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",233
	;[234] CONST CS_RED					= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",234
	;[235] CONST CS_TAN					= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",235
	;[236] CONST CS_DARKGREEN			= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",236
	;[237] CONST CS_GREEN				= $0005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",237
	;[238] CONST CS_YELLOW				= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",238
	;[239] CONST CS_WHITE				= $0007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",239
	;[240] CONST CS_GREY				= $1000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",240
	;[241] CONST CS_CYAN				= $1001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",241
	;[242] CONST CS_ORANGE				= $1002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",242
	;[243] CONST CS_BROWN				= $1003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",243
	;[244] CONST CS_PINK				= $1004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",244
	;[245] CONST CS_LIGHTBLUE			= $1005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",245
	;[246] CONST CS_YELLOWGREEN			= $1006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",246
	;[247] CONST CS_PURPLE				= $1007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",247
	;[248] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",248
	;[249] CONST CS_CARD_DATA_MASK		= $07F8		' Mask to get the background card's data.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",249
	;[250] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",250
	;[251] CONST CS_ADVANCE			= $2000		' Advance the colour stack by one position.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",251
	;[252] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",252
	;[253] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",253
	;[254] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",254
	;[255] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",255
	;[256] REM COLORS - Mode 1 (Foreground Background)
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",256
	;[257] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",257
	;[258] REM Foreground.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",258
	;[259] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",259
	;[260] REM Notes:
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",260
	;[261] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",261
	;[262] REM - Only one foreground colour permitted per background card.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",262
	;[263] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",263
	;[264] CONST FG_BLACK				= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",264
	;[265] CONST FG_BLUE				= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",265
	;[266] CONST FG_RED				= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",266
	;[267] CONST FG_TAN				= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",267
	;[268] CONST FG_DARKGREEN			= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",268
	;[269] CONST FG_GREEN				= $0005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",269
	;[270] CONST FG_YELLOW				= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",270
	;[271] CONST FG_WHITE				= $0007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",271
	;[272] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",272
	;[273] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",273
	;[274] REM Background.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",274
	;[275] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",275
	;[276] REM Notes:
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",276
	;[277] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",277
	;[278] REM - Only one background colour permitted per background card.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",278
	;[279] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",279
	;[280] CONST BG_BLACK				= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",280
	;[281] CONST BG_BLUE				= $0200
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",281
	;[282] CONST BG_RED				= $0400
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",282
	;[283] CONST BG_TAN				= $0600
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",283
	;[284] CONST BG_DARKGREEN			= $0800
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",284
	;[285] CONST BG_GREEN				= $0A00
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",285
	;[286] CONST BG_YELLOW				= $0C00
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",286
	;[287] CONST BG_WHITE				= $0E00
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",287
	;[288] CONST BG_GREY				= $1000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",288
	;[289] CONST BG_CYAN				= $1200
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",289
	;[290] CONST BG_ORANGE				= $1400
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",290
	;[291] CONST BG_BROWN				= $1600
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",291
	;[292] CONST BG_PINK				= $1800
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",292
	;[293] CONST BG_LIGHTBLUE			= $1A00
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",293
	;[294] CONST BG_YELLOWGREEN		= $1C00
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",294
	;[295] CONST BG_PURPLE				= $1E00
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",295
	;[296] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",296
	;[297] CONST FGBG_CARD_DATA_MASK	= $01F8		' Mask to get the background card's data.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",297
	;[298] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",298
	;[299] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",299
	;[300] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",300
	;[301] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",301
	;[302] REM Sprites.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",302
	;[303] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",303
	;[304] REM Note: For use with "sprite" command.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",304
	;[305] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",305
	;[306] REM X
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",306
	;[307] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",307
	;[308] REM Note: Add these constants to the sprite command's X parameter.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",308
	;[309] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",309
	;[310] CONST HIT					= $0100		' Enable the sprite's collision detection.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",310
	;[311] CONST VISIBLE				= $0200		' Make the sprite visible.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",311
	;[312] CONST ZOOMX2				= $0400		' Make the sprite twice the width.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",312
	;[313] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",313
	;[314] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",314
	;[315] REM Y
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",315
	;[316] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",316
	;[317] REM Note: Add these constants to the sprite command's Y parameter.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",317
	;[318] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",318
	;[319] CONST DOUBLEY				= $0080		' Make a double height sprite (with 2 GRAM cards).
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",319
	;[320] CONST ZOOMY2				= $0100		' Make the sprite twice (x2) the normal height.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",320
	;[321] CONST ZOOMY4				= $0200		' Make the sprite quadruple (x4) the normal height.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",321
	;[322] CONST ZOOMY8				= $0300		' Make the sprite octuple (x8) the normal height.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",322
	;[323] CONST FLIPX					= $0400		' Flip/mirror the sprite in X.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",323
	;[324] CONST FLIPY					= $0800		' Flip/mirror the sprite in Y.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",324
	;[325] CONST MIRROR				= $0C00		' Flip/mirror the sprite in both X and Y.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",325
	;[326] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",326
	;[327] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",327
	;[328] REM A
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",328
	;[329] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",329
	;[330] REM Notes:
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",330
	;[331] REM - Combine to create the sprite command's A parameter.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",331
	;[332] REM - Only one colour per sprite.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",332
	;[333] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",333
	;[334] CONST GRAM				= $0800		' Sprite's data is located in GRAM.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",334
	;[335] CONST BEHIND				= $2000		' Sprite is behind the background.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",335
	;[336] CONST SPR_BLACK			= $0000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",336
	;[337] CONST SPR_BLUE			= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",337
	;[338] CONST SPR_RED			= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",338
	;[339] CONST SPR_TAN			= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",339
	;[340] CONST SPR_DARKGREEN		= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",340
	;[341] CONST SPR_GREEN			= $0005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",341
	;[342] CONST SPR_YELLOW			= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",342
	;[343] CONST SPR_WHITE			= $0007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",343
	;[344] CONST SPR_GREY			= $1000
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",344
	;[345] CONST SPR_CYAN			= $1001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",345
	;[346] CONST SPR_ORANGE			= $1002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",346
	;[347] CONST SPR_BROWN			= $1003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",347
	;[348] CONST SPR_PINK			= $1004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",348
	;[349] CONST SPR_LIGHTBLUE		= $1005
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",349
	;[350] CONST SPR_YELLOWGREEN		= $1006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",350
	;[351] CONST SPR_PURPLE			= $1007
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",351
	;[352] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",352
	;[353] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",353
	;[354] REM GRAM numbers.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",354
	;[355] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",355
	;[356] REM Note: For use in the sprite command's parameter A.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",356
	;[357] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",357
	;[358] CONST SPR00 				= $0800
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",358
	;[359] CONST SPR01 				= $0808
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",359
	;[360] CONST SPR02 				= $0810
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",360
	;[361] CONST SPR03 				= $0818
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",361
	;[362] CONST SPR04 				= $0820
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",362
	;[363] CONST SPR05 				= $0828
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",363
	;[364] CONST SPR06 				= $0830
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",364
	;[365] CONST SPR07 				= $0838
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",365
	;[366] CONST SPR08 				= $0840
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",366
	;[367] CONST SPR09 				= $0848
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",367
	;[368] CONST SPR10 				= $0850
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",368
	;[369] CONST SPR11 				= $0858
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",369
	;[370] CONST SPR12 				= $0860
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",370
	;[371] CONST SPR13 				= $0868
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",371
	;[372] CONST SPR14 				= $0870
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",372
	;[373] CONST SPR15 				= $0878
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",373
	;[374] CONST SPR16 				= $0880
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",374
	;[375] CONST SPR17 				= $0888
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",375
	;[376] CONST SPR18 				= $0890
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",376
	;[377] CONST SPR19 				= $0898
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",377
	;[378] CONST SPR20 				= $08A0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",378
	;[379] CONST SPR21 				= $08A8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",379
	;[380] CONST SPR22 				= $08B0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",380
	;[381] CONST SPR23 				= $08B8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",381
	;[382] CONST SPR24 				= $08C0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",382
	;[383] CONST SPR25 				= $08C8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",383
	;[384] CONST SPR26 				= $08D0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",384
	;[385] CONST SPR27 				= $08D8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",385
	;[386] CONST SPR28 				= $08E0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",386
	;[387] CONST SPR29 				= $08E8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",387
	;[388] CONST SPR30 				= $08F0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",388
	;[389] CONST SPR31 				= $08F8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",389
	;[390] CONST SPR32 				= $0900
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",390
	;[391] CONST SPR33 				= $0908
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",391
	;[392] CONST SPR34 				= $0910
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",392
	;[393] CONST SPR35 				= $0918
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",393
	;[394] CONST SPR36 				= $0920
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",394
	;[395] CONST SPR37 				= $0928
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",395
	;[396] CONST SPR38 				= $0930
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",396
	;[397] CONST SPR39 				= $0938
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",397
	;[398] CONST SPR40 				= $0940
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",398
	;[399] CONST SPR41 				= $0948
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",399
	;[400] CONST SPR42 				= $0950
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",400
	;[401] CONST SPR43 				= $0958
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",401
	;[402] CONST SPR44 				= $0960
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",402
	;[403] CONST SPR45 				= $0968
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",403
	;[404] CONST SPR46 				= $0970
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",404
	;[405] CONST SPR47 				= $0978
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",405
	;[406] CONST SPR48 				= $0980
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",406
	;[407] CONST SPR49 				= $0988
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",407
	;[408] CONST SPR50 				= $0990
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",408
	;[409] CONST SPR51 				= $0998
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",409
	;[410] CONST SPR52 				= $09A0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",410
	;[411] CONST SPR53 				= $09A8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",411
	;[412] CONST SPR54 				= $09B0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",412
	;[413] CONST SPR55 				= $09B8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",413
	;[414] CONST SPR56 				= $09C0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",414
	;[415] CONST SPR57 				= $09C8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",415
	;[416] CONST SPR58 				= $09D0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",416
	;[417] CONST SPR59 				= $09D8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",417
	;[418] CONST SPR60 				= $09E0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",418
	;[419] CONST SPR61 				= $09E8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",419
	;[420] CONST SPR62 				= $09F0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",420
	;[421] CONST SPR63 				= $09F8
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",421
	;[422] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",422
	;[423] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",423
	;[424] REM Sprite collision.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",424
	;[425] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",425
	;[426] REM Notes:
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",426
	;[427] REM - For use with variables COL0, COL1, COL2, COL3, COL4, COL5, COL6 and COL7.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",427
	;[428] REM - More than one collision can occur simultaneously.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",428
	;[429] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",429
	;[430] CONST HIT_SPRITE0			= $0001		' Sprite collided with sprite 0.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",430
	;[431] CONST HIT_SPRITE1			= $0002		' Sprite collided with sprite 1.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",431
	;[432] CONST HIT_SPRITE2			= $0004		' Sprite collided with sprite 2.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",432
	;[433] CONST HIT_SPRITE3			= $0008		' Sprite collided with sprite 3.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",433
	;[434] CONST HIT_SPRITE4			= $0010		' Sprite collided with sprite 4.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",434
	;[435] CONST HIT_SPRITE5			= $0020		' Sprite collided with sprite 5.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",435
	;[436] CONST HIT_SPRITE6			= $0040		' Sprite collided with sprite 6.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",436
	;[437] CONST HIT_SPRITE7			= $0080		' Sprite collided with sprite 7.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",437
	;[438] CONST HIT_BACKGROUND		= $0100		' Sprite collided with a background pixel.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",438
	;[439] CONST HIT_BORDER			= $0200		' Sprite collided with the top/bottom/left/right border.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",439
	;[440] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",440
	;[441] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",441
	;[442] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",442
	;[443] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",443
	;[444] REM DISC - Compass.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",444
	;[445] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",445
	;[446] REM   NW         N         NE
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",446
	;[447] REM     \   NNW  |  NNE   /
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",447
	;[448] REM       \      |      /
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",448
	;[449] REM         \    |    /
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",449
	;[450] REM    WNW    \  |  /    ENE
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",450
	;[451] REM             \|/
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",451
	;[452] REM  W ----------+---------- E
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",452
	;[453] REM             /|\ 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",453
	;[454] REM    WSW    /  |  \    ESE
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",454
	;[455] REM         /    |    \
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",455
	;[456] REM       /      |      \
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",456
	;[457] REM     /   SSW  |  SSE   \
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",457
	;[458] REM   SW         S         SE
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",458
	;[459] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",459
	;[460] REM Notes:
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",460
	;[461] REM - North points upwards on the hand controller.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",461
	;[462] REM - Directions are listed in a clockwise manner.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",462
	;[463] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",463
	;[464] CONST DISC_NORTH			= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",464
	;[465] CONST DISC_NORTH_NORTH_EAST = $0014
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",465
	;[466] CONST DISC_NORTH_EAST		= $0016
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",466
	;[467] CONST DISC_EAST_NORTH_EAST	= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",467
	;[468] CONST DISC_EAST				= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",468
	;[469] CONST DISC_EAST_SOUTH_EAST	= $0012
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",469
	;[470] CONST DISC_SOUTH_EAST		= $0013
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",470
	;[471] CONST DISC_SOUTH_SOUTH_EAST	= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",471
	;[472] CONST DISC_SOUTH			= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",472
	;[473] CONST DISC_SOUTH_SOUTH_WEST	= $0011
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",473
	;[474] CONST DISC_SOUTH_WEST		= $0025
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",474
	;[475] CONST DISC_WEST_SOUTH_WEST	= $0009
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",475
	;[476] CONST DISC_WEST				= $0008
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",476
	;[477] CONST DISC_WEST_NORTH_WEST	= $0018
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",477
	;[478] CONST DISC_NORTH_WEST		= $001C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",478
	;[479] CONST DISC_NORTH_NORTH_WEST	= $000C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",479
	;[480] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",480
	;[481] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",481
	;[482] REM DISC - Compass abbreviated versions.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",482
	;[483] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",483
	;[484] CONST DISC_N				= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",484
	;[485] CONST DISC_NNE 				= $0014
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",485
	;[486] CONST DISC_NE				= $0016
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",486
	;[487] CONST DISC_ENE				= $0006
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",487
	;[488] CONST DISC_E				= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",488
	;[489] CONST DISC_ESE				= $0012
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",489
	;[490] CONST DISC_SE				= $0013
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",490
	;[491] CONST DISC_SSE				= $0003
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",491
	;[492] CONST DISC_S				= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",492
	;[493] CONST DISC_SSW				= $0011
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",493
	;[494] CONST DISC_SW				= $0019
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",494
	;[495] CONST DISC_WSW				= $0009
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",495
	;[496] CONST DISC_W				= $0008
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",496
	;[497] CONST DISC_WNW				= $0018
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",497
	;[498] CONST DISC_NW				= $001C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",498
	;[499] CONST DISC_NNW				= $000C
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",499
	;[500] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",500
	;[501] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",501
	;[502] REM DISC - Directions.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",502
	;[503] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",503
	;[504] CONST DISC_UP				= $0004
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",504
	;[505] CONST DISC_UP_RIGHT			= $0016		' Up and right diagonal.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",505
	;[506] CONST DISC_RIGHT			= $0002
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",506
	;[507] CONST DISC_DOWN_RIGHT		= $0013		' Down  and right diagonal.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",507
	;[508] CONST DISC_DOWN				= $0001
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",508
	;[509] CONST DISC_DOWN_LEFT		= $0019		' Down and left diagonal.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",509
	;[510] CONST DISC_LEFT				= $0008
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",510
	;[511] CONST DISC_UP_LEFT			= $001C		' Up and left diagonal.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",511
	;[512] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",512
	;[513] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",513
	;[514] REM DISK - Mask.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",514
	;[515] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",515
	;[516] CONST DISK_MASK				= $001F
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",516
	;[517] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",517
	;[518] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",518
	;[519] REM Controller - Keypad.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",519
	;[520] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",520
	;[521] CONST KEYPAD_0				= 72
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",521
	;[522] CONST KEYPAD_1				= 129
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",522
	;[523] CONST KEYPAD_2				= 65
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",523
	;[524] CONST KEYPAD_3				= 33
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",524
	;[525] CONST KEYPAD_4				= 130
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",525
	;[526] CONST KEYPAD_5				= 66
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",526
	;[527] CONST KEYPAD_6				= 34
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",527
	;[528] CONST KEYPAD_7				= 132
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",528
	;[529] CONST KEYPAD_8				= 68
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",529
	;[530] CONST KEYPAD_9				= 36
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",530
	;[531] CONST KEYPAD_CLEAR			= 136
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",531
	;[532] CONST KEYPAD_ENTER			= 40
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",532
	;[533] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",533
	;[534] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",534
	;[535] REM Controller - Side buttons.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",535
	;[536] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",536
	;[537] CONST BUTTON_TOP_LEFT		= $A0		' Top left and top right are the same button.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",537
	;[538] CONST BUTTON_TOP_RIGHT		= $A0		' Note: Bit 6 is low. 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",538
	;[539] CONST BUTTON_BOTTOM_LEFT	= $60		' Note: Bit 7 is low.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",539
	;[540] CONST BUTTON_BOTTOM_RIGHT	= $C0		' Note: Bit 5 is low
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",540
	;[541] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",541
	;[542] REM Abbreviated versions.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",542
	;[543] CONST BUTTON_1				= $A0		' Top left or top right.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",543
	;[544] CONST BUTTON_2				= $60		' Bottom left.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",544
	;[545] CONST BUTTON_3				= $C0		' Bottom right.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",545
	;[546] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",546
	;[547] REM Mask.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",547
	;[548] CONST BUTTON_MASK			= $E0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",548
	;[549] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",549
	;[550] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",550
	;[551] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",551
	;[552] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",552
	;[553] REM Useful functions.
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",553
	;[554] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",554
	;[555] DEF FN screenpos(aColumn, aRow)		= (((aRow)*BACKGROUND_COLUMNS)+(aColumn))
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",555
	;[556] DEF FN screenaddr(aColumn, aRow)	= (BACKTAB+(((aRow)*BACKGROUND_COLUMNS)+(aColumn)))
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",556
	;[557] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",557
	;[558] DEF FN setspritex(aSpriteNo,anXPosition)	= #mobshadow(aSpriteNo)=(#mobshadow(aSpriteNo) and $ff00)+anXPosition
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",558
	;[559] DEF FN setspritey(aSpriteNo,aYPosition)		= #mobshadow(aSpriteNo+8)=(#mobshadow(aSpriteNo+8) and $ff80)+aYPosition
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",559
	;[560] DEF FN resetsprite(aSpriteNo)				= sprite aSpriteNo, 0, 0, 0
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",560
	;[561] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",561
	;[562] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",562
	;[563] 
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",563
	;[564] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",564
	;[565] REM END
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",565
	;[566] REM -------------------------------------------------------------------------
	SRCFILE "C:\Apps\Intellivision\bin\constants.bas",566
	;ENDFILE
	;FILE IntyMusic.bas
	;[5] PLAY FULL
	SRCFILE "IntyMusic.bas",5
	MVII #5,R3
	MVO R3,_music_mode
	;[6] DIM iMusicNoteColor(3)		'Note color 
	SRCFILE "IntyMusic.bas",6
	;[7] DIM #iMusicPianoColorA(3)
	SRCFILE "IntyMusic.bas",7
	;[8] DIM #iMusicPianoColorB(3)
	SRCFILE "IntyMusic.bas",8
	;[9] 
	SRCFILE "IntyMusic.bas",9
	;[10] '========================== Options #1 - customization ========================================
	SRCFILE "IntyMusic.bas",10
	;[11] CONST INTYMUSIC_AUTO_SCROLL = 1			'0 to pause at notes, 1 to always scroll
	SRCFILE "IntyMusic.bas",11
	;[12] CONST INTYMUSIC_FANFOLD = 1				'1 to alternate colors, like classic dot-matrix paper
	SRCFILE "IntyMusic.bas",12
	;[13] 
	SRCFILE "IntyMusic.bas",13
	;[14] '--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
	SRCFILE "IntyMusic.bas",14
	;[15] CONST INTYMUSIC_STAFF_COLOR = FG_BLACK		'-- staff color 
	SRCFILE "IntyMusic.bas",15
	;[16] CONST INTYMUSIC_TITLE_COLOR=FG_BLUE			'---Song title Color
	SRCFILE "IntyMusic.bas",16
	;[17] 
	SRCFILE "IntyMusic.bas",17
	;[18] '--- Music note color, by voice channel (drawn on top, scrolls down)----
	SRCFILE "IntyMusic.bas",18
	;[19] iMusicNoteColor(0)=FG_DARKGREEN
	SRCFILE "IntyMusic.bas",19
	MVII #4,R0
	MVO R0,Q3
	;[20] iMusicNoteColor(1)=FG_RED
	SRCFILE "IntyMusic.bas",20
	MVII #2,R0
	MVO R0,Q3+1
	;[21] iMusicNoteColor(2)=FG_BLUE
	SRCFILE "IntyMusic.bas",21
	MVII #1,R0
	MVO R0,Q3+2
	;[22] 
	SRCFILE "IntyMusic.bas",22
	;[23] '--- Piano key color, by voice channel ---- 2nd set for flash effect. Use same colors on 2nd set to disable blink
	SRCFILE "IntyMusic.bas",23
	;[24] ' SPR_BLACK,SPR_BLUE,SPR_RED,SPR_TAN,SPR_DARKGREEN,SPR_GREEN,SPR_YELLOW,SPR_WHITE,SPR_GREY,SPR_CYAN,SPR_ORANGE,SPR_BROWN,SPR_PINK,SPR_LIGHTBLUE,SPR_YELLOWGREEN,SPR_PURPLE			7
	SRCFILE "IntyMusic.bas",24
	;[25] '--1st set---
	SRCFILE "IntyMusic.bas",25
	;[26] #iMusicPianoColorA(0)=SPR_DARKGREEN
	SRCFILE "IntyMusic.bas",26
	MVII #4,R0
	MVO R0,Q4
	;[27] #iMusicPianoColorA(1)=SPR_RED
	SRCFILE "IntyMusic.bas",27
	MVII #2,R0
	MVO R0,Q4+1
	;[28] #iMusicPianoColorA(2)=SPR_BLUE
	SRCFILE "IntyMusic.bas",28
	MVII #1,R0
	MVO R0,Q4+2
	;[29] '--2nd set, flash---
	SRCFILE "IntyMusic.bas",29
	;[30] #iMusicPianoColorB(0)=SPR_GREEN
	SRCFILE "IntyMusic.bas",30
	MOVR R3,R0
	MVO R0,Q5
	;[31] #iMusicPianoColorB(1)=SPR_ORANGE
	SRCFILE "IntyMusic.bas",31
	MVII #4098,R0
	MVO R0,Q5+1
	;[32] #iMusicPianoColorB(2)=SPR_LIGHTBLUE
	SRCFILE "IntyMusic.bas",32
	MVII #4101,R0
	MVO R0,Q5+2
	;[33] 
	SRCFILE "IntyMusic.bas",33
	;[34] '----Color stack----alternating background colors 
	SRCFILE "IntyMusic.bas",34
	;[35] 'STACK_BLACK,STACK_BLUE,STACK_RED,STACK_TAN,STACK_DARKGREEN,STACK_GREEN,STACK_YELLOW,STACK_WHITE,STACK_GREY,STACK_CYAN,STACK_ORANGE,STACK_BROWN,STACK_PINK,STACK_LIGHTBLUE,STACK_YELLOWGREEN,STACK_PURPLE
	SRCFILE "IntyMusic.bas",35
	;[36] BORDER BORDER_WHITE,0
	SRCFILE "IntyMusic.bas",36
	MVII #7,R0
	MVO R0,_border_color
	CLRR R0
	MVO R0,_border_mask
	;[37] MODE 0,STACK_WHITE,STACK_TAN,STACK_WHITE,STACK_TAN
	SRCFILE "IntyMusic.bas",37
	MVII #29495,R0
	MVO R0,_color
	MVII #1,R0
	MVO R0,_mode_select
	;[38] 'MODE 0,STACK_GREY,STACK_LIGHTBLUE,STACK_WHITE,STACK_CYAN
	SRCFILE "IntyMusic.bas",38
	;[39] 
	SRCFILE "IntyMusic.bas",39
	;[40] CONST INTYMUSIC_SONG_TITLE = 1		'0 to disable song title, should eliminate flicker 
	SRCFILE "IntyMusic.bas",40
	;[41] 
	SRCFILE "IntyMusic.bas",41
	;[42] '========================== Options #1 End =============================================
	SRCFILE "IntyMusic.bas",42
	;[43] 
	SRCFILE "IntyMusic.bas",43
	;[44] '-----Required------ 
	SRCFILE "IntyMusic.bas",44
	;[45] INCLUDE "IntyMusicPlayer.bas"
	SRCFILE "IntyMusic.bas",45
	;FILE IntyMusicPlayer.bas
	;[1] 'IntyMusic by Marco A. Marrero.  Started at 7-30-2016, version 8/3/2016
	SRCFILE "IntyMusicPlayer.bas",1
	;[2] 'IntyMusic_Player.bas | Main code.
	SRCFILE "IntyMusicPlayer.bas",2
	;[3] 'Public domain, feel free to use/modify. Feel free to contact me in the Intellivision Programming forum @ AtariAge.com
	SRCFILE "IntyMusicPlayer.bas",3
	;[4] WAIT:DEFINE 0,16,Sprite0
	SRCFILE "IntyMusicPlayer.bas",4
	CALL _wait
	CLRR R0
	MVO R0,_gram_target
	MVII #16,R0
	MVO R0,_gram_total
	MVII #Q6,R0
	MVO R0,_gram_bitmap
	;[5] WAIT:DEFINE 16,16,Sprite16
	SRCFILE "IntyMusicPlayer.bas",5
	CALL _wait
	MVII #16,R0
	MVO R0,_gram_target
	MVO R0,_gram_total
	MVII #Q7,R0
	MVO R0,_gram_bitmap
	;[6] 
	SRCFILE "IntyMusicPlayer.bas",6
	;[7] '--- variables to copy values from IntyBasic_epilogue -----
	SRCFILE "IntyMusicPlayer.bas",7
	;[8] DIM #iMusicNote(3)		'Notes 0,1,2	(from IntyBasic_epilogue)
	SRCFILE "IntyMusicPlayer.bas",8
	;[9] DIM #iMusicVol(3)			'Volume (from IntyBasic_epilogue)
	SRCFILE "IntyMusicPlayer.bas",9
	;[10] DIM #iMusicInst(3)		'Instrument. I need to match volume history...
	SRCFILE "IntyMusicPlayer.bas",10
	;[11] DIM #iMusicTime(2)		'Time counter (from IntyBasic_epilogue, _music_tc, Time base -1 (_music_t)
	SRCFILE "IntyMusicPlayer.bas",11
	;[12] 
	SRCFILE "IntyMusicPlayer.bas",12
	;[13] DIM iMusicNoteLast(3)		'Previous notes
	SRCFILE "IntyMusicPlayer.bas",13
	;[14] DIM iMusicVolumeLast(3)	'store last volume values, compare with instrument... sigh...
	SRCFILE "IntyMusicPlayer.bas",14
	;[15] DIM iMusicDrawNote(3)		'Draw new note?
	SRCFILE "IntyMusicPlayer.bas",15
	;[16] 
	SRCFILE "IntyMusicPlayer.bas",16
	;[17] IF INTYMUSIC_FANFOLD THEN #IntyMusicBlink=CS_ADVANCE ELSE #IntyMusicBlink=0
	SRCFILE "IntyMusicPlayer.bas",17
	MVII #1,R0
	TSTR R0
	BEQ T1
	MVII #8192,R0
	MVO R0,V1
	B T2
T1:
	CLRR R0
	MVO R0,V1
T2:
	;[18] 
	SRCFILE "IntyMusicPlayer.bas",18
	;[19] '---------------
	SRCFILE "IntyMusicPlayer.bas",19
	;[20] IntyMusicReset:
	SRCFILE "IntyMusicPlayer.bas",20
	; INTYMUSICRESET
Q15:	;[21] 
	SRCFILE "IntyMusicPlayer.bas",21
	;[22] '----show title screen and credits--- also prints vertical song name ---
	SRCFILE "IntyMusicPlayer.bas",22
	;[23] GOSUB IntyMusicInit
	SRCFILE "IntyMusicPlayer.bas",23
	CALL Q16
	;[24] 
	SRCFILE "IntyMusicPlayer.bas",24
	;[25] '-----init----
	SRCFILE "IntyMusicPlayer.bas",25
	;[26] iMusicScroll=0			'Need to scroll screen?
	SRCFILE "IntyMusicPlayer.bas",26
	CLRR R0
	MVO R0,V2
	;[27] Toggle=1
	SRCFILE "IntyMusicPlayer.bas",27
	MVII #1,R0
	MVO R0,V3
	;[28] KeyClear=0
	SRCFILE "IntyMusicPlayer.bas",28
	CLRR R0
	MVO R0,V4
	;[29] 
	SRCFILE "IntyMusicPlayer.bas",29
	;[30] '---- main loop -----
	SRCFILE "IntyMusicPlayer.bas",30
	;[31] PLAY MyMusic
	SRCFILE "IntyMusicPlayer.bas",31
	MVII #Q17,R0
	CALL _play_music
	;[32] PlayLoop:
	SRCFILE "IntyMusicPlayer.bas",32
	; PLAYLOOP
Q18:	;[33] 	'---- user reset? ----
	SRCFILE "IntyMusicPlayer.bas",33
	;[34] 	IF Cont.KEY=12 THEN 
	SRCFILE "IntyMusicPlayer.bas",34
	MVI _cnt1_key,R0
	CMPI #12,R0
	BNE $+4
	MVI _cnt2_key,R0
	CMPI #12,R0
	BNE T3
	;[35] 		KeyClear=1
	SRCFILE "IntyMusicPlayer.bas",35
	MVII #1,R0
	MVO R0,V4
	;[36] 	ELSE
	SRCFILE "IntyMusicPlayer.bas",36
	B T4
T3:
	;[37] 		IF KeyClear THEN 
	SRCFILE "IntyMusicPlayer.bas",37
	MVI V4,R0
	TSTR R0
	BEQ T5
	;[38] 			IF Cont.KEY=10 THEN 
	SRCFILE "IntyMusicPlayer.bas",38
	MVI _cnt1_key,R0
	CMPI #12,R0
	BNE $+4
	MVI _cnt2_key,R0
	CMPI #10,R0
	BNE T6
	;[39] 				PLAY OFF						
	SRCFILE "IntyMusicPlayer.bas",39
	CLRR R0
	CALL _play_music
	;[40] 				SOUND 0,1,0:	SOUND 1,1,0:	SOUND 2,1,0:SOUND 4,1,$38
	SRCFILE "IntyMusicPlayer.bas",40
	MVII #1,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	MVII #1,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	CLRR R0
	MVO R0,508
	MVII #1,R0
	MVO R0,498
	SWAP R0
	MVO R0,502
	CLRR R0
	MVO R0,509
	MVII #1,R0
	MVO R0,505
	MVII #56,R0
	MVO R0,504
	;[41] 				CALL IMUSICKILL	'works too well...
	SRCFILE "IntyMusicPlayer.bas",41
	CALL F19
	;[42] 				GOTO IntyMusicReset
	SRCFILE "IntyMusicPlayer.bas",42
	B Q15
	;[43] 			END IF
	SRCFILE "IntyMusicPlayer.bas",43
T6:
	;[44] 		END IF
	SRCFILE "IntyMusicPlayer.bas",44
T5:
	;[45] 		KeyClear=0
	SRCFILE "IntyMusicPlayer.bas",45
	CLRR R0
	MVO R0,V4
	;[46] 	END IF	
	SRCFILE "IntyMusicPlayer.bas",46
T4:
	;[47] 	'-------------------
	SRCFILE "IntyMusicPlayer.bas",47
	;[48] 
	SRCFILE "IntyMusicPlayer.bas",48
	;[49] 	'--I will keep track of notes playing for each voice, and also keep track of volume to know if same note played again
	SRCFILE "IntyMusicPlayer.bas",49
	;[50] 	'---it seems it does not work most times...
	SRCFILE "IntyMusicPlayer.bas",50
	;[51] 	FOR iMusicX=0 to 2
	SRCFILE "IntyMusicPlayer.bas",51
	CLRR R0
	MVO R0,V5
T7:
	;[52] 		iMusicNoteLast(iMusicX)=#iMusicNote(iMusicX)	
	SRCFILE "IntyMusicPlayer.bas",52
	MVII #Q8,R3
	ADD V5,R3
	MVI@ R3,R0
	MVII #Q12,R3
	ADD V5,R3
	MVO@ R0,R3
	;[53] 		iMusicVolumeLast(iMusicX)=#iMusicVol(iMusicX)
	SRCFILE "IntyMusicPlayer.bas",53
	MVII #Q9,R3
	ADD V5,R3
	MVI@ R3,R0
	MVII #Q13,R3
	ADD V5,R3
	MVO@ R0,R3
	;[54] 	NEXT iMusicX	
	SRCFILE "IntyMusicPlayer.bas",54
	MVI V5,R0
	INCR R0
	MVO R0,V5
	CMPI #2,R0
	BLE T7
	;[55] 		
	SRCFILE "IntyMusicPlayer.bas",55
	;[56] 	'--Get values from IntyBasic_epilogue ASM
	SRCFILE "IntyMusicPlayer.bas",56
	;[57] 	Call IMUSICGETINFO(VARPTR #iMusicVol(0), VARPTR #iMusicNote(0), VARPTR #iMusicTime(0), VARPTR #iMusicInst(0))	
	SRCFILE "IntyMusicPlayer.bas",57
	MVII #Q9,R0
	MVII #Q8,R1
	MVII #Q11,R2
	MVII #Q10,R3
	CALL F20
	;[58] 	
	SRCFILE "IntyMusicPlayer.bas",58
	;[59] 	'Use IntyBasic music counter (_music_tc), if its 1 I can check if new notes are playing	
	SRCFILE "IntyMusicPlayer.bas",59
	;[60] 	IF #iMusicTime(1)=#iMusicTime(0) THEN	 '<----IF Song Speed is 1, player will freeze.. comment this, uncomment below:
	SRCFILE "IntyMusicPlayer.bas",60
	MVI Q11+1,R0
	MVI Q11,R1
	CMPR R1,R0
	BNE T8
	;[61] 	'IF #iMusicTime(1)=1 THEN	
	SRCFILE "IntyMusicPlayer.bas",61
	;[62] 	
	SRCFILE "IntyMusicPlayer.bas",62
	;[63] 		'--- check if note changed, or, if same note plays again by checking instrument volume 
	SRCFILE "IntyMusicPlayer.bas",63
	;[64] 		iMusicScroll=0		
	SRCFILE "IntyMusicPlayer.bas",64
	CLRR R0
	MVO R0,V2
	;[65] 		FOR iMusicX=0 to 2	
	SRCFILE "IntyMusicPlayer.bas",65
	MVO R0,V5
T9:
	;[66] 			IntyNote=0
	SRCFILE "IntyMusicPlayer.bas",66
	CLRR R0
	MVO R0,V6
	;[67] 			IF iMusicNoteLast(iMusicX)<>#iMusicNote(iMusicX) THEN GOTO GotIntyNote	'note changed
	SRCFILE "IntyMusicPlayer.bas",67
	MVII #Q12,R3
	ADD V5,R3
	MVI@ R3,R0
	MVII #Q8,R3
	ADD V5,R3
	CMP@ R3,R0
	BNE Q21
	;[68] 			
	SRCFILE "IntyMusicPlayer.bas",68
	;[69] 			'Same note? check last volume. piano: 14,13 clarinet: 13,14 bass: 12,13 flute:10,12
	SRCFILE "IntyMusicPlayer.bas",69
	;[70] 			iMusicVolCheck=#iMusicVol(iMusicX)
	SRCFILE "IntyMusicPlayer.bas",70
	MVII #Q9,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V7
	;[71] 			iMusicVolLast=iMusicVolumeLast(iMusicX)
	SRCFILE "IntyMusicPlayer.bas",71
	MVII #Q13,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V8
	;[72] 			iMusicInst=#iMusicInst(iMusicX)
	SRCFILE "IntyMusicPlayer.bas",72
	MVII #Q10,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V9
	;[73] 			IF iMusicInst=0 THEN IF iMusicVolLast=14 AND iMusicVolCheck=13 THEN GOTO GotIntyNote	'piano
	SRCFILE "IntyMusicPlayer.bas",73
	MVI V9,R0
	TSTR R0
	BNE T11
	MVI V8,R0
	CMPI #14,R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V7,R1
	CMPI #13,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BNE Q21
T11:
	;[74] 			IF iMusicInst=64 THEN IF iMusicVolLast=13 AND iMusicVolCheck=14 THEN GOTO GotIntyNote	'clarinet
	SRCFILE "IntyMusicPlayer.bas",74
	MVI V9,R0
	CMPI #64,R0
	BNE T13
	MVI V8,R0
	CMPI #13,R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V7,R1
	CMPI #14,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BNE Q21
T13:
	;[75] 			IF iMusicInst=128 THEN IF iMusicVolLast=10 AND iMusicVolCheck=12 THEN GOTO GotIntyNote	'flute 
	SRCFILE "IntyMusicPlayer.bas",75
	MVI V9,R0
	CMPI #128,R0
	BNE T15
	MVI V8,R0
	CMPI #10,R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V7,R1
	CMPI #12,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BNE Q21
T15:
	;[76] 			IF iMusicInst=192 THEN IF iMusicVolLast=12 AND iMusicVolCheck=13 THEN GOTO GotIntyNote	'bass
	SRCFILE "IntyMusicPlayer.bas",76
	MVI V9,R0
	CMPI #192,R0
	BNE T17
	MVI V8,R0
	CMPI #12,R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V7,R1
	CMPI #13,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BNE Q21
T17:
	;[77] 			GOTO GotIntyNoteFail
	SRCFILE "IntyMusicPlayer.bas",77
	B Q22
	;[78] 
	SRCFILE "IntyMusicPlayer.bas",78
	;[79] 		GotIntyNote:			
	SRCFILE "IntyMusicPlayer.bas",79
	; GOTINTYNOTE
Q21:	;[80] 			IntyNote=iMusicNoteColor(iMusicX)	'NonZero, indicating note will play
	SRCFILE "IntyMusicPlayer.bas",80
	MVII #Q3,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V6
	;[81] 			IF IntyNote=0 THEN IntyNote=1
	SRCFILE "IntyMusicPlayer.bas",81
	MVI V6,R0
	TSTR R0
	BNE T19
	MVII #1,R0
	MVO R0,V6
T19:
	;[82] 			
	SRCFILE "IntyMusicPlayer.bas",82
	;[83] 		GotIntyNoteFail:
	SRCFILE "IntyMusicPlayer.bas",83
	; GOTINTYNOTEFAIL
Q22:	;[84] 			iMusicDrawNote(iMusicX)=IntyNote
	SRCFILE "IntyMusicPlayer.bas",84
	MVI V6,R0
	MVII #Q14,R3
	ADD V5,R3
	MVO@ R0,R3
	;[85] 			iMusicScroll=iMusicScroll+IntyNote			
	SRCFILE "IntyMusicPlayer.bas",85
	MVI V2,R0
	ADD V6,R0
	MVO R0,V2
	;[86] 		NEXT iMusicX
	SRCFILE "IntyMusicPlayer.bas",86
	MVI V5,R0
	INCR R0
	MVO R0,V5
	CMPI #2,R0
	BLE T9
	;[87] 		
	SRCFILE "IntyMusicPlayer.bas",87
	;[88] 		'---------------- SCROLL, DRAW MUSIC ----------------------------		
	SRCFILE "IntyMusicPlayer.bas",88
	;[89] 		'--- Theres very little time after VBLANK, I had to rearrange things here to draw bottom display first
	SRCFILE "IntyMusicPlayer.bas",89
	;[90] 		IF (INTYMUSIC_AUTO_SCROLL OR iMusicScroll) THEN 			
	SRCFILE "IntyMusicPlayer.bas",90
	MVII #1,R0
	MVI V2,R4
	COMR R4
	ANDR R4,R0
	XOR V2,R0
	BEQ T20
	;[91] 			Toggle=Toggle XOR 1	'Toggle piano key color
	SRCFILE "IntyMusicPlayer.bas",91
	MVI V3,R0
	XORI #1,R0
	MVO R0,V3
	;[92] 							
	SRCFILE "IntyMusicPlayer.bas",92
	;[93] 			WAIT:CALL MUSICSCROLL		'Scroll... I am only scrolling part of the screen
	SRCFILE "IntyMusicPlayer.bas",93
	CALL _wait
	CALL F25
	;[94] 						
	SRCFILE "IntyMusicPlayer.bas",94
	;[95] 			'- Draw piano--- (not needed, it will not scroll away anymore)
	SRCFILE "IntyMusicPlayer.bas",95
	;[96] 			'FOR iMusicX=0 TO 18:#BACKTAB(200+iMusicX)= IntyPiano(iMusicX):NEXT iMusicX	
	SRCFILE "IntyMusicPlayer.bas",96
	;[97] 			
	SRCFILE "IntyMusicPlayer.bas",97
	;[98] 			'---Alternate colors---
	SRCFILE "IntyMusicPlayer.bas",98
	;[99] 			#BACKTAB(0)=#IntyMusicBlink						
	SRCFILE "IntyMusicPlayer.bas",99
	MVI V1,R0
	MVO R0,Q2
	;[100] 			#BACKTAB(220)=#IntyMusicBlink
	SRCFILE "IntyMusicPlayer.bas",100
	MVI V1,R0
	MVO R0,Q2+220
	;[101] 			
	SRCFILE "IntyMusicPlayer.bas",101
	;[102] 			PRINT AT 221		'<--- Do NOT remove!	
	SRCFILE "IntyMusicPlayer.bas",102
	MVII #733,R0
	MVO R0,_screen
	;[103] 			
	SRCFILE "IntyMusicPlayer.bas",103
	;[104] 			'---Draw lower bottom note data,ex. C3# A4 B5-----	
	SRCFILE "IntyMusicPlayer.bas",104
	;[105] 			FOR iMusicX=0 TO 2
	SRCFILE "IntyMusicPlayer.bas",105
	CLRR R0
	MVO R0,V5
T21:
	;[106] 				IntyNote=#iMusicNote(iMusicX)	'Get note value to use in look-up tables 
	SRCFILE "IntyMusicPlayer.bas",106
	MVII #Q8,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V6
	;[107] 				#x=iMusicNoteColor(iMusicX)	'Get note color
	SRCFILE "IntyMusicPlayer.bas",107
	MVII #Q3,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V10
	;[108] 								
	SRCFILE "IntyMusicPlayer.bas",108
	;[109] 				PRINT 2280+iMusicDrawNote(iMusicX)	'Note + blink	'Print "\285" (2280=285*8)
	SRCFILE "IntyMusicPlayer.bas",109
	MVII #Q14,R3
	ADD V5,R3
	MVI@ R3,R0
	ADDI #2280,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[110] 				
	SRCFILE "IntyMusicPlayer.bas",110
	;[111] 				'Note text,ex. C5#
	SRCFILE "IntyMusicPlayer.bas",111
	;[112] 				PRINT IntyNoteLetter(IntyNote)+#x,IntyNoteSharp(IntyNote)+#x,IntyNoteOctave(IntyNote)+#x,0,0
	SRCFILE "IntyMusicPlayer.bas",112
	MVII #Q26,R3
	ADD V6,R3
	MVI@ R3,R0
	ADD V10,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	MVII #Q27,R3
	ADD V6,R3
	MVI@ R3,R0
	ADD V10,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	MVII #Q28,R3
	ADD V6,R3
	MVI@ R3,R0
	ADD V10,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	CLRR R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[113] 			NEXT iMusicX
	SRCFILE "IntyMusicPlayer.bas",113
	MVI V5,R0
	INCR R0
	MVO R0,V5
	CMPI #2,R0
	BLE T21
	;[114] 								
	SRCFILE "IntyMusicPlayer.bas",114
	;[115] 			'---Draw bottom left piano, lefmost key... I cannot waste time erasing other piano keys that scrolled down
	SRCFILE "IntyMusicPlayer.bas",115
	;[116] 			'RINT 2272 'PRINT "\284"			
	SRCFILE "IntyMusicPlayer.bas",116
	;[117] 			
	SRCFILE "IntyMusicPlayer.bas",117
	;[118] 			'----Done updating lower screen. Clear top line, draw staff---
	SRCFILE "IntyMusicPlayer.bas",118
	;[119] 			FOR iMusicX=1 TO 18
	SRCFILE "IntyMusicPlayer.bas",119
	MVII #1,R0
	MVO R0,V5
T22:
	;[120] 				#BACKTAB(iMusicX)=IntyNoteBlankLine(iMusicX)	+ INTYMUSIC_STAFF_COLOR
	SRCFILE "IntyMusicPlayer.bas",120
	MVII #Q29,R3
	ADD V5,R3
	MVI@ R3,R0
	MVII #Q2,R3
	ADD V5,R3
	MVO@ R0,R3
	;[121] 			NEXT iMusicX
	SRCFILE "IntyMusicPlayer.bas",121
	MVI V5,R0
	INCR R0
	MVO R0,V5
	CMPI #18,R0
	BLE T22
	;[122] 			
	SRCFILE "IntyMusicPlayer.bas",122
	;[123] 			'---Use sprites to "hilite" piano keys and draw notes-----
	SRCFILE "IntyMusicPlayer.bas",123
	;[124] 			FOR iMusicX=0 TO 2
	SRCFILE "IntyMusicPlayer.bas",124
	CLRR R0
	MVO R0,V5
T23:
	;[125] 				IntyNote=#iMusicNote(iMusicX)	'--Get note 
	SRCFILE "IntyMusicPlayer.bas",125
	MVII #Q8,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V6
	;[126] 				
	SRCFILE "IntyMusicPlayer.bas",126
	;[127] 				'---Draw Note. Up to 2 notes per card. I used a spreadsheet to create lookup data, card, position, etc.--
	SRCFILE "IntyMusicPlayer.bas",127
	;[128] 				IF iMusicDrawNote(iMusicX) THEN #BACKTAB(IntyNoteOnscreen(IntyNote))=IntyNoteGRAM(IntyNote) + iMusicNoteColor(iMusicX)				
	SRCFILE "IntyMusicPlayer.bas",128
	MVII #Q14,R3
	ADD V5,R3
	MVI@ R3,R0
	TSTR R0
	BEQ T24
	MVII #Q31,R3
	ADD V6,R3
	MVI@ R3,R0
	MVII #Q3,R3
	ADD V5,R3
	ADD@ R3,R0
	MVII #Q2,R1
	MVII #Q30,R3
	ADD V6,R3
	ADD@ R3,R1
	MVO@ R0,R1
T24:
	;[129] 				
	SRCFILE "IntyMusicPlayer.bas",129
	;[130] 				'---Overlay sprites on piano keys. Flash colors---
	SRCFILE "IntyMusicPlayer.bas",130
	;[131] 				IF Toggle THEN #x=#iMusicPianoColorA(iMusicX) ELSE #x=#iMusicPianoColorB(iMusicX)
	SRCFILE "IntyMusicPlayer.bas",131
	MVI V3,R0
	TSTR R0
	BEQ T25
	MVII #Q4,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V10
	B T26
T25:
	MVII #Q5,R3
	ADD V5,R3
	MVI@ R3,R0
	MVO R0,V10
T26:
	;[132] 				SPRITE iMusicX,16 + VISIBLE + IntyPianoSpriteOffset(IntyNote),88 + ZOOMY2, IntyPianoSprite(IntyNote) + #x
	SRCFILE "IntyMusicPlayer.bas",132
	MVII #Q1,R0
	ADD V5,R0
	MOVR R0,R4
	MVII #Q32,R3
	ADD V6,R3
	MVI@ R3,R0
	ADDI #528,R0
	MVO@ R0,R4
	MVII #344,R0
	ADDI #7,R4
	MVO@ R0,R4
	MVII #Q33,R3
	ADD V6,R3
	MVI@ R3,R0
	ADD V10,R0
	ADDI #7,R4
	MVO@ R0,R4
	;[133] 			NEXT iMusicX		
	SRCFILE "IntyMusicPlayer.bas",133
	MVI V5,R0
	INCR R0
	MVO R0,V5
	CMPI #2,R0
	BLE T23
	;[134] 		END IF '<----- Scroll			
	SRCFILE "IntyMusicPlayer.bas",134
T20:
	;[135] 	ELSE	
	SRCFILE "IntyMusicPlayer.bas",135
	B T27
T8:
	;[136] 		WAIT
	SRCFILE "IntyMusicPlayer.bas",136
	CALL _wait
	;[137] 	END IF '<-----#iMusicTime()
	SRCFILE "IntyMusicPlayer.bas",137
T27:
	;[138] 	
	SRCFILE "IntyMusicPlayer.bas",138
	;[139] GOTO PlayLoop
	SRCFILE "IntyMusicPlayer.bas",139
	B Q18
	;[140] 
	SRCFILE "IntyMusicPlayer.bas",140
	;[141] '    _______________
	SRCFILE "IntyMusicPlayer.bas",141
	;[142] '___/ IMUSICGETINFO \________________________________________________________________
	SRCFILE "IntyMusicPlayer.bas",142
	;[143] 'Get IntyBasic_epilogue data onto IntyBasic. Ill copy note and volume
	SRCFILE "IntyMusicPlayer.bas",143
	;[144] 'Call IMUSICGETINFO(VARPTR #iMusicVol(0), VARPTR #iMusicNote(0), VARPTR #iMusicTime(0), VARPTR #iMusicInst(0))	
	SRCFILE "IntyMusicPlayer.bas",144
	;[145] ASM IMUSICGETINFO: PROC	
	SRCFILE "IntyMusicPlayer.bas",145
IMUSICGETINFO: PROC	
	;[146] 'r0 = 1st parameter, VARPTR #iMusicVol(0)
	SRCFILE "IntyMusicPlayer.bas",146
	;[147] 'r1 = 2nd parameter, VARPTR #iMusicNote(0)
	SRCFILE "IntyMusicPlayer.bas",147
	;[148] 'r2 = 3rd parameter, VARPTR #iMusicTime(0)
	SRCFILE "IntyMusicPlayer.bas",148
	;[149] 'r3 = 4rd parameter, VARPTR #iInstrument(0)
	SRCFILE "IntyMusicPlayer.bas",149
	;[150] 'asm pshr r5				;push return
	SRCFILE "IntyMusicPlayer.bas",150
	;[151] 		
	SRCFILE "IntyMusicPlayer.bas",151
	;[152] '--- Get iIntruments ---------
	SRCFILE "IntyMusicPlayer.bas",152
	;[153] 	asm movr	r3,r4				; r3 --> r4 		
	SRCFILE "IntyMusicPlayer.bas",153
 movr	r3,r4				; r3 --> r4 		
	;[154] 	asm mvi _music_i1,r3
	SRCFILE "IntyMusicPlayer.bas",154
 mvi _music_i1,r3
	;[155] 	asm mvo@ r3,r4				; r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",155
 mvo@ r3,r4				; r3 --> [r4++]
	;[156] 	asm mvi _music_i2,r3
	SRCFILE "IntyMusicPlayer.bas",156
 mvi _music_i2,r3
	;[157] 	asm mvo@ r3,r4				; r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",157
 mvo@ r3,r4				; r3 --> [r4++]
	;[158] 	asm mvi _music_i3,r3
	SRCFILE "IntyMusicPlayer.bas",158
 mvi _music_i3,r3
	;[159] 	asm mvo@ r3,r4				; r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",159
 mvo@ r3,r4				; r3 --> [r4++]
	;[160] 
	SRCFILE "IntyMusicPlayer.bas",160
	;[161] '---- get volume, to know when same note played again ---
	SRCFILE "IntyMusicPlayer.bas",161
	;[162] 	asm movr	r0,r4			;r0 --> r4 (r4=r0=&#iMusicVol(0))
	SRCFILE "IntyMusicPlayer.bas",162
 movr	r0,r4			;r0 --> r4 (r4=r0=&#iMusicVol(0))
	;[163] 	
	SRCFILE "IntyMusicPlayer.bas",163
	;[164] 	asm mvi	_music_vol1,r3	;  --> r3	
	SRCFILE "IntyMusicPlayer.bas",164
 mvi	_music_vol1,r3	;  --> r3	
	;[165] 	asm mvo@ r3,r4			;r2 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",165
 mvo@ r3,r4			;r2 --> [r4++]
	;[166] 	asm mvi	_music_vol2,r3	; --> r3
	SRCFILE "IntyMusicPlayer.bas",166
 mvi	_music_vol2,r3	; --> r3
	;[167] 	asm mvo@ r3,r4			;r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",167
 mvo@ r3,r4			;r3 --> [r4++]
	;[168] 	asm mvi	_music_vol3,r3	; --> r3
	SRCFILE "IntyMusicPlayer.bas",168
 mvi	_music_vol3,r3	; --> r3
	;[169] 	asm mvo@ r3,r4			;r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",169
 mvo@ r3,r4			;r3 --> [r4++]
	;[170] 		
	SRCFILE "IntyMusicPlayer.bas",170
	;[171] '--- get notes ---
	SRCFILE "IntyMusicPlayer.bas",171
	;[172] 	asm movr	r1,r4			;r1 --> r4. (r4=&#iMusicNote(0))
	SRCFILE "IntyMusicPlayer.bas",172
 movr	r1,r4			;r1 --> r4. (r4=&#iMusicNote(0))
	;[173] 	asm mvi	_music_n1,r3		;_music_n1 --> r3
	SRCFILE "IntyMusicPlayer.bas",173
 mvi	_music_n1,r3		;_music_n1 --> r3
	;[174] 	asm mvo@ r3,r4			;r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",174
 mvo@ r3,r4			;r3 --> [r4++]
	;[175] 	asm mvi	_music_n2,r3 	;_music_n2 --> r3
	SRCFILE "IntyMusicPlayer.bas",175
 mvi	_music_n2,r3 	;_music_n2 --> r3
	;[176] 	asm mvo@ r3,r4			;r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",176
 mvo@ r3,r4			;r3 --> [r4++]
	;[177] 	asm mvi	_music_n3,r3		;_music_n3 --> r3
	SRCFILE "IntyMusicPlayer.bas",177
 mvi	_music_n3,r3		;_music_n3 --> r3
	;[178] 	asm mvo@ r3,r4			;r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",178
 mvo@ r3,r4			;r3 --> [r4++]
	;[179] 	
	SRCFILE "IntyMusicPlayer.bas",179
	;[180] '--- get time counter and time base --------
	SRCFILE "IntyMusicPlayer.bas",180
	;[181] 	asm movr r2,r4				;r2 --> r4  (r4= &#iMusicTime(0))
	SRCFILE "IntyMusicPlayer.bas",181
 movr r2,r4				;r2 --> r4  (r4= &#iMusicTime(0))
	;[182] 	asm mvi _music_t,r3			; _music_t --> r3 (time base)
	SRCFILE "IntyMusicPlayer.bas",182
 mvi _music_t,r3			; _music_t --> r3 (time base)
	;[183] 	asm decr r3 					; r3--
	SRCFILE "IntyMusicPlayer.bas",183
 decr r3 					; r3--
	;[184] 	asm mvo@ r3,r4				; r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",184
 mvo@ r3,r4				; r3 --> [r4++]
	;[185] 	asm mvi	_music_tc,r3			; _music_t --> r3 (time)	
	SRCFILE "IntyMusicPlayer.bas",185
 mvi	_music_tc,r3			; _music_t --> r3 (time)	
	;[186] 	asm mvo@ r3,r4				; r3 --> [r4++]
	SRCFILE "IntyMusicPlayer.bas",186
 mvo@ r3,r4				; r3 --> [r4++]
	;[187] 
	SRCFILE "IntyMusicPlayer.bas",187
	;[188] '-------------------------------------------------------------	
	SRCFILE "IntyMusicPlayer.bas",188
	;[189] 	asm jr	r5				;return 
	SRCFILE "IntyMusicPlayer.bas",189
 jr	r5				;return 
	;[190] 	
	SRCFILE "IntyMusicPlayer.bas",190
	;[191] 	'asm	pulr pc				;return 
	SRCFILE "IntyMusicPlayer.bas",191
	;[192] 	'asm mvi@ r3,r3				; Get pointer, r3=[r3] 
	SRCFILE "IntyMusicPlayer.bas",192
	;[193] 	'asm xorr	r3,r3 			; r3=0
	SRCFILE "IntyMusicPlayer.bas",193
	;[194] asm ENDP
	SRCFILE "IntyMusicPlayer.bas",194
 ENDP
	;[195] 
	SRCFILE "IntyMusicPlayer.bas",195
	;[196] '    ____________
	SRCFILE "IntyMusicPlayer.bas",196
	;[197] '___/ MUSICSCROLL \____________________ 
	SRCFILE "IntyMusicPlayer.bas",197
	;[198] 'Only Scroll 10 rows, and only columns 2 to 18 (17 lines)
	SRCFILE "IntyMusicPlayer.bas",198
	;[199] ASM MUSICSCROLL: PROC	
	SRCFILE "IntyMusicPlayer.bas",199
MUSICSCROLL: PROC	
	;[200] 		
	SRCFILE "IntyMusicPlayer.bas",200
	;[201] 	asm mvii #$0200 + 198,r2		;#BackTAB + 198--> R2
	SRCFILE "IntyMusicPlayer.bas",201
 mvii #$0200 + 198,r2		;#BackTAB + 198--> R2
	;[202] 	asm mvii	#$0200 + 178,r3		;Line above --> r3 
	SRCFILE "IntyMusicPlayer.bas",202
 mvii	#$0200 + 178,r3		;Line above --> r3 
	;[203] 	asm mvii #9,r1				;Loop 9 lines
	SRCFILE "IntyMusicPlayer.bas",203
 mvii #9,r1				;Loop 9 lines
	;[204] 	asm mvii #2,r4				;Skip 2 chars
	SRCFILE "IntyMusicPlayer.bas",204
 mvii #2,r4				;Skip 2 chars
	;[205] 	
	SRCFILE "IntyMusicPlayer.bas",205
	;[206] asm @@CopyLoop:
	SRCFILE "IntyMusicPlayer.bas",206
@@CopyLoop:
	;[207] 	asm REPEAT 18
	SRCFILE "IntyMusicPlayer.bas",207
 REPEAT 18
	;[208] 		asm mvi@ r3,r0		;[r3] --> R0
	SRCFILE "IntyMusicPlayer.bas",208
 mvi@ r3,r0		;[r3] --> R0
	;[209] 		asm decr r3
	SRCFILE "IntyMusicPlayer.bas",209
 decr r3
	;[210] 		asm mvo@ r0,r2		;r0 --> [R2]		
	SRCFILE "IntyMusicPlayer.bas",210
 mvo@ r0,r2		;r0 --> [R2]		
	;[211] 		asm decr r2 
	SRCFILE "IntyMusicPlayer.bas",211
 decr r2 
	;[212] 	asm ENDR
	SRCFILE "IntyMusicPlayer.bas",212
 ENDR
	;[213] 	
	SRCFILE "IntyMusicPlayer.bas",213
	;[214] 	asm subr r4,r2		;skip 3 chars 
	SRCFILE "IntyMusicPlayer.bas",214
 subr r4,r2		;skip 3 chars 
	;[215] 	asm subr r4,r3 
	SRCFILE "IntyMusicPlayer.bas",215
 subr r4,r3 
	;[216] 	
	SRCFILE "IntyMusicPlayer.bas",216
	;[217] 	asm decr r1			;done row..
	SRCFILE "IntyMusicPlayer.bas",217
 decr r1			;done row..
	;[218] 	asm bne @@CopyLoop
	SRCFILE "IntyMusicPlayer.bas",218
 bne @@CopyLoop
	;[219] 	
	SRCFILE "IntyMusicPlayer.bas",219
	;[220] 	asm jr	r5				;return
	SRCFILE "IntyMusicPlayer.bas",220
 jr	r5				;return
	;[221] 	'asm	pulr pc				;return 
	SRCFILE "IntyMusicPlayer.bas",221
	;[222] asm ENDP		
	SRCFILE "IntyMusicPlayer.bas",222
 ENDP		
	;[223] 
	SRCFILE "IntyMusicPlayer.bas",223
	;[224] '    ____________
	SRCFILE "IntyMusicPlayer.bas",224
	;[225] '___/ IMUSICKILL \___________________________
	SRCFILE "IntyMusicPlayer.bas",225
	;[226] 'PLAY NONE seems not to work.... 
	SRCFILE "IntyMusicPlayer.bas",226
	;[227] ASM IMUSICKILL: PROC	
	SRCFILE "IntyMusicPlayer.bas",227
IMUSICKILL: PROC	
	;[228] 		
	SRCFILE "IntyMusicPlayer.bas",228
	;[229] '--- kill notes ---
	SRCFILE "IntyMusicPlayer.bas",229
	;[230] 	asm xorr r0,r0			;clear r0
	SRCFILE "IntyMusicPlayer.bas",230
 xorr r0,r0			;clear r0
	;[231] 	asm mvo	r0,_music_n1
	SRCFILE "IntyMusicPlayer.bas",231
 mvo	r0,_music_n1
	;[232] 	asm mvo	r0,_music_n2
	SRCFILE "IntyMusicPlayer.bas",232
 mvo	r0,_music_n2
	;[233] 	asm mvo 	r0,_music_n3
	SRCFILE "IntyMusicPlayer.bas",233
 mvo 	r0,_music_n3
	;[234] 	asm jr	r5				;return 
	SRCFILE "IntyMusicPlayer.bas",234
 jr	r5				;return 
	;[235] asm ENDP
	SRCFILE "IntyMusicPlayer.bas",235
 ENDP
	;[236] 
	SRCFILE "IntyMusicPlayer.bas",236
	;[237] '==============================================================================
	SRCFILE "IntyMusicPlayer.bas",237
	;[238] 'From IntyBasic_epilogue.asm
	SRCFILE "IntyMusicPlayer.bas",238
	;[239] '_music_table:	RMB 1	; Note table
	SRCFILE "IntyMusicPlayer.bas",239
	;[240] '_music_start:	RMB 1	; Start of music
	SRCFILE "IntyMusicPlayer.bas",240
	;[241] '_music_p:	RMB 1	; Pointer to music
	SRCFILE "IntyMusicPlayer.bas",241
	;[242] '- - - - - - -
	SRCFILE "IntyMusicPlayer.bas",242
	;[243] '_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
	SRCFILE "IntyMusicPlayer.bas",243
	;[244] '_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
	SRCFILE "IntyMusicPlayer.bas",244
	;[245] '_music_tc:  RMB 1       ; Time counter
	SRCFILE "IntyMusicPlayer.bas",245
	;[246] '_music_t:   RMB 1       ; Time base
	SRCFILE "IntyMusicPlayer.bas",246
	;[247] '_music_i1:  RMB 1       ; Instrument 1 
	SRCFILE "IntyMusicPlayer.bas",247
	;[248] '_music_s1:  RMB 1       ; Sample pointer 1
	SRCFILE "IntyMusicPlayer.bas",248
	;[249] '_music_n1:  RMB 1       ; Note 1
	SRCFILE "IntyMusicPlayer.bas",249
	;[250] '_music_i2:  RMB 1       ; Instrument 2
	SRCFILE "IntyMusicPlayer.bas",250
	;[251] '_music_s2:  RMB 1       ; Sample pointer 2
	SRCFILE "IntyMusicPlayer.bas",251
	;[252] '_music_n2:  RMB 1       ; Note 2
	SRCFILE "IntyMusicPlayer.bas",252
	;[253] '_music_i3:  RMB 1       ; Instrument 3
	SRCFILE "IntyMusicPlayer.bas",253
	;[254] '_music_s3:  RMB 1       ; Sample pointer 3
	SRCFILE "IntyMusicPlayer.bas",254
	;[255] '_music_n3:  RMB 1       ; Note 3
	SRCFILE "IntyMusicPlayer.bas",255
	;[256] '_music_s4:  RMB 1       ; Sample pointer 4
	SRCFILE "IntyMusicPlayer.bas",256
	;[257] '_music_n4:  RMB 1       ; Note 4 (really it's drum)
	SRCFILE "IntyMusicPlayer.bas",257
	;[258] '-----
	SRCFILE "IntyMusicPlayer.bas",258
	;[259] '_music_freq10:	RMB 1   ; Low byte frequency A
	SRCFILE "IntyMusicPlayer.bas",259
	;[260] '_music_freq20:	RMB 1   ; Low byte frequency B
	SRCFILE "IntyMusicPlayer.bas",260
	;[261] '_music_freq30:	RMB 1   ; Low byte frequency C
	SRCFILE "IntyMusicPlayer.bas",261
	;[262] '_music_freq11:	RMB 1   ; High byte frequency A
	SRCFILE "IntyMusicPlayer.bas",262
	;[263] '_music_freq21:	RMB 1   ; High byte frequency B
	SRCFILE "IntyMusicPlayer.bas",263
	;[264] '_music_freq31:	RMB 1   ; High byte frequency C
	SRCFILE "IntyMusicPlayer.bas",264
	;[265] '_music_mix:	RMB 1   ; Mixer
	SRCFILE "IntyMusicPlayer.bas",265
	;[266] '_music_noise:	RMB 1   ; Noise
	SRCFILE "IntyMusicPlayer.bas",266
	;[267] '_music_vol1:	RMB 1   ; Volume A
	SRCFILE "IntyMusicPlayer.bas",267
	;[268] '_music_vol2:	RMB 1   ; Volume B
	SRCFILE "IntyMusicPlayer.bas",268
	;[269] '_music_vol3:	RMB 1   ; Volume C
	SRCFILE "IntyMusicPlayer.bas",269
	;[270] '_music_vol:	RMB 1	; Global music volume
	SRCFILE "IntyMusicPlayer.bas",270
	;[271] 
	SRCFILE "IntyMusicPlayer.bas",271
	;ENDFILE
	;FILE IntyMusic.bas
	;[46] INCLUDE "IntyMusicCredits.bas"		
	SRCFILE "IntyMusic.bas",46
	;FILE IntyMusicCredits.bas
	;[1] 
	SRCFILE "IntyMusicCredits.bas",1
	;[2] 	
	SRCFILE "IntyMusicCredits.bas",2
	;[3] 'Draw initial screen... otherwise it will flicker badly, especially fanfold
	SRCFILE "IntyMusicCredits.bas",3
	;[4] IntyMusicInit: PROCEDURE
	SRCFILE "IntyMusicCredits.bas",4
	; INTYMUSICINIT
Q16:	PROC
	BEGIN
	;[5] 	resetsprite(0):resetsprite(1):resetsprite(2)	
	SRCFILE "IntyMusicCredits.bas",5
	CLRR R0
	MVO R0,_mobs
	MVO R0,_mobs+8
	NOP
	MVO R0,_mobs+16
	MVO R0,_mobs+1
	NOP
	MVO R0,_mobs+9
	MVO R0,_mobs+17
	NOP
	MVO R0,_mobs+2
	MVO R0,_mobs+10
	NOP
	MVO R0,_mobs+18
	;[6] 	CLS
	SRCFILE "IntyMusicCredits.bas",6
	CALL CLRSCR
	MVII #512,R0
	MVO R0,_screen
	;[7] 	WAIT
	SRCFILE "IntyMusicCredits.bas",7
	CALL _wait
	;[8] 	iMusicX=0			
	SRCFILE "IntyMusicCredits.bas",8
	CLRR R0
	MVO R0,V5
	;[9] 	'--draw a bit of the staff	
	SRCFILE "IntyMusicCredits.bas",9
	;[10] 	FOR #x=0 TO 3*20
	SRCFILE "IntyMusicCredits.bas",10
	MVO R0,V10
T28:
	;[11] 		#BACKTAB(#x)=IntyNoteBlankLine(iMusicX)	+ INTYMUSIC_STAFF_COLOR
	SRCFILE "IntyMusicCredits.bas",11
	MVII #Q29,R3
	ADD V5,R3
	MVI@ R3,R0
	MVII #Q2,R3
	ADD V10,R3
	MVO@ R0,R3
	;[12] 		iMusicX=iMusicX+1:IF iMusicX>19 THEN iMusicX=0
	SRCFILE "IntyMusicCredits.bas",12
	MVI V5,R0
	INCR R0
	MVO R0,V5
	MVI V5,R0
	CMPI #19,R0
	BLE T29
	CLRR R0
	MVO R0,V5
T29:
	;[13] 	NEXT #x
	SRCFILE "IntyMusicCredits.bas",13
	MVI V10,R0
	INCR R0
	MVO R0,V10
	CMPI #60,R0
	BLE T28
	;[14] 
	SRCFILE "IntyMusicCredits.bas",14
	;[15] 	'Draw &
	SRCFILE "IntyMusicCredits.bas",15
	;[16] 	PRINT AT 9 COLOR 0,"\277\269\272\261"
	SRCFILE "IntyMusicCredits.bas",16
	MVII #521,R0
	MVO R0,_screen
	CLRR R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2216,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[17] 	PRINT AT 29,"\278\270\273\262"
	SRCFILE "IntyMusicCredits.bas",17
	MVII #541,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #2224,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	XORI #248,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[18] 	
	SRCFILE "IntyMusicCredits.bas",18
	;[19] 	'draw )
	SRCFILE "IntyMusicCredits.bas",19
	;[20] 	PRINT AT 5,"\271\263"
	SRCFILE "IntyMusicCredits.bas",20
	MVII #517,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #2168,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[21] 	PRINT AT 25,"\273\262"
	SRCFILE "IntyMusicCredits.bas",21
	MVII #537,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #2184,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[22] 	PRINT AT 46,"\279"
	SRCFILE "IntyMusicCredits.bas",22
	MVII #558,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #2232,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[23] 		
	SRCFILE "IntyMusicCredits.bas",23
	;[24] 	IntyNote=19:GOSUB DrawPiano	'Draw all 20 piano keys
	SRCFILE "IntyMusicCredits.bas",24
	MVII #19,R0
	MVO R0,V6
	CALL Q35
	;[25] 
	SRCFILE "IntyMusicCredits.bas",25
	;[26] 	'---me---		
	SRCFILE "IntyMusicCredits.bas",26
	;[27] 	PRINT AT 160 COLOR FG_BLUE,"\285"
	SRCFILE "IntyMusicCredits.bas",27
	MVII #672,R0
	MVO R0,_screen
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2280,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[28] 	PRINT COLOR FG_BLACK," IntyMusic Player "
	SRCFILE "IntyMusicCredits.bas",28
	CLRR R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	XORI #328,R0
	MVO@ R0,R4
	XORI #824,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #928,R0
	MVO@ R0,R4
	XORI #960,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #80,R0
	MVO@ R0,R4
	XORI #536,R0
	MVO@ R0,R4
	XORI #384,R0
	MVO@ R0,R4
	XORI #992,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #656,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[29] 	PRINT COLOR FG_BLUE,"\285"
	SRCFILE "IntyMusicCredits.bas",29
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2280,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[30] 	PRINT AT 182 COLOR FG_BLACK,"by Marco Marrero"
	SRCFILE "IntyMusicCredits.bas",30
	MVII #694,R0
	MVO R0,_screen
	CLRR R0
	MVO R0,_color
	MVI _screen,R4
	MVII #528,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #712,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #632,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[31] 
	SRCFILE "IntyMusicCredits.bas",31
	;[32] 	GOSUB IntyMusicInit_Credits
	SRCFILE "IntyMusicCredits.bas",32
	CALL Q36
	;[33] 	GOSUB DrawPiano
	SRCFILE "IntyMusicCredits.bas",33
	CALL Q35
	;[34] 			
	SRCFILE "IntyMusicCredits.bas",34
	;[35] 	PRINT AT 221 COLOR FG_BLUE,"Any button to play"	
	SRCFILE "IntyMusicCredits.bas",35
	MVII #733,R0
	MVO R0,_screen
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #264,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #888,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #712,R0
	MVO@ R0,R4
	XORI #528,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #624,R0
	MVO@ R0,R4
	XORI #672,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #632,R0
	MVO@ R0,R4
	XORI #640,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[36] 	'---Alternate colors
	SRCFILE "IntyMusicCredits.bas",36
	;[37] 	IF INTYMUSIC_FANFOLD THEN
	SRCFILE "IntyMusicCredits.bas",37
	MVII #1,R0
	TSTR R0
	BEQ T30
	;[38] 		iMusicX=0
	SRCFILE "IntyMusicCredits.bas",38
	CLRR R0
	MVO R0,V5
	;[39] 		FOR #x=1 TO 10
	SRCFILE "IntyMusicCredits.bas",39
	MVII #1,R0
	MVO R0,V10
T31:
	;[40] 			#BACKTAB(iMusicX)=#BACKTAB(iMusicX)+#IntyMusicBlink
	SRCFILE "IntyMusicCredits.bas",40
	MVII #Q2,R3
	ADD V5,R3
	MVI@ R3,R0
	ADD V1,R0
	MVO@ R0,R3
	;[41] 			iMusicX=iMusicX+20
	SRCFILE "IntyMusicCredits.bas",41
	MVI V5,R0
	ADDI #20,R0
	MVO R0,V5
	;[42] 		NEXT #x		
	SRCFILE "IntyMusicCredits.bas",42
	MVI V10,R0
	INCR R0
	MVO R0,V10
	CMPI #10,R0
	BLE T31
	;[43] 	END IF
	SRCFILE "IntyMusicCredits.bas",43
T30:
	;[44] 	
	SRCFILE "IntyMusicCredits.bas",44
	;[45] 	GOSUB WaitForKeyDownThenUp	
	SRCFILE "IntyMusicCredits.bas",45
	CALL Q37
	;[46] 	
	SRCFILE "IntyMusicCredits.bas",46
	;[47] 	'--key pressed... start... Scroll title away, slowly	
	SRCFILE "IntyMusicCredits.bas",47
	;[48] 	FOR iMusicX=1 TO 12
	SRCFILE "IntyMusicCredits.bas",48
	MVII #1,R0
	MVO R0,V5
T32:
	;[49] 		SCROLL 0,0,3		'Scroll upwards (move things down)
	SRCFILE "IntyMusicCredits.bas",49
	CLRR R0
	MVO R0,_scroll_x
	MVO R0,_scroll_y
	MVII #3,R0
	MVO R0,_scroll_d
	;[50] 		WAIT		
	SRCFILE "IntyMusicCredits.bas",50
	CALL _wait
	;[51] 		GOSUB DrawPiano
	SRCFILE "IntyMusicCredits.bas",51
	CALL Q35
	;[52] 		GOSUB DrawEmptyTopStaff
	SRCFILE "IntyMusicCredits.bas",52
	CALL Q38
	;[53] 		
	SRCFILE "IntyMusicCredits.bas",53
	;[54] 		'Print song name --
	SRCFILE "IntyMusicCredits.bas",54
	;[55] 		IF INTYMUSIC_SONG_TITLE THEN 
	SRCFILE "IntyMusicCredits.bas",55
	MVII #1,R0
	TSTR R0
	BEQ T33
	;[56] 			#BACKTAB(19)=MyMusicName(12-iMusicX)*8 + INTYMUSIC_TITLE_COLOR	
	SRCFILE "IntyMusicCredits.bas",56
	MVII #Q39,R1
	MVII #12,R2
	SUB V5,R2
	ADDR R2,R1
	MVI@ R1,R0
	SLL R0,2
	ADDR R0,R0
	INCR R0
	MVO R0,Q2+19
	;[57] 			IF iMusicX<10 THEN
	SRCFILE "IntyMusicCredits.bas",57
	MVI V5,R0
	CMPI #10,R0
	BGE T34
	;[58] 				#BACKTAB(239)=0
	SRCFILE "IntyMusicCredits.bas",58
	CLRR R0
	MVO R0,Q2+239
	;[59] 			ELSEIF iMusicX=10 THEN 
	SRCFILE "IntyMusicCredits.bas",59
	B T35
T34:
	MVI V5,R0
	CMPI #10,R0
	BNE T36
	;[60] 				IntyNote=18
	SRCFILE "IntyMusicCredits.bas",60
	MVII #18,R0
	MVO R0,V6
	;[61] 				#BACKTAB(219)=0		'Stop drawing all piano keys when title is nearby			
	SRCFILE "IntyMusicCredits.bas",61
	CLRR R0
	MVO R0,Q2+219
	;[62] 				#BACKTAB(239)=0
	SRCFILE "IntyMusicCredits.bas",62
	MVO R0,Q2+239
	;[63] 			END IF
	SRCFILE "IntyMusicCredits.bas",63
T35:
T36:
	;[64] 		END IF
	SRCFILE "IntyMusicCredits.bas",64
T33:
	;[65] 			
	SRCFILE "IntyMusicCredits.bas",65
	;[66] 		'sleep...		
	SRCFILE "IntyMusicCredits.bas",66
	;[67] 		FOR #x=1 TO 5: WAIT:NEXT #x
	SRCFILE "IntyMusicCredits.bas",67
	MVII #1,R0
	MVO R0,V10
T37:
	CALL _wait
	MVI V10,R0
	INCR R0
	MVO R0,V10
	CMPI #5,R0
	BLE T37
	;[68] 	NEXT iMusicX 
	SRCFILE "IntyMusicCredits.bas",68
	MVI V5,R0
	INCR R0
	MVO R0,V5
	CMPI #12,R0
	BLE T32
	;[69] END
	SRCFILE "IntyMusicCredits.bas",69
	RETURN
	ENDP
	;[70] 
	SRCFILE "IntyMusicCredits.bas",70
	;[71] WaitForKeyDownThenUp: procedure
	SRCFILE "IntyMusicCredits.bas",71
	; WAITFORKEYDOWNTHENUP
Q37:	PROC
	BEGIN
	;[72] 	' Wait for a key to be pressed. Ignore CLR
	SRCFILE "IntyMusicCredits.bas",72
	;[73] 	DO
	SRCFILE "IntyMusicCredits.bas",73
T38:
	;[74] 		do 
	SRCFILE "IntyMusicCredits.bas",74
T40:
	;[75] 			wait
	SRCFILE "IntyMusicCredits.bas",75
	CALL _wait
	;[76] 		loop while CONT=0 OR CONT.KEY=10
	SRCFILE "IntyMusicCredits.bas",76
	MVI 510,R0
	XOR 511,R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI _cnt1_key,R1
	CMPI #12,R1
	BNE $+4
	MVI _cnt2_key,R1
	CMPI #10,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T42
	B T40
T42:
	;[77] 
	SRCFILE "IntyMusicCredits.bas",77
	;[78] 		' Wait for a key to be released
	SRCFILE "IntyMusicCredits.bas",78
	;[79] 		do 
	SRCFILE "IntyMusicCredits.bas",79
T43:
	;[80] 			wait
	SRCFILE "IntyMusicCredits.bas",80
	CALL _wait
	;[81] 		loop while CONT<>0
	SRCFILE "IntyMusicCredits.bas",81
	MVI 510,R0
	XOR 511,R0
	BEQ T45
	B T43
T45:
	;[82] 	LOOP WHILE CONT.KEY=10
	SRCFILE "IntyMusicCredits.bas",82
	MVI _cnt1_key,R0
	CMPI #12,R0
	BNE $+4
	MVI _cnt2_key,R0
	CMPI #10,R0
	BNE T46
	B T38
T46:
	;[83] end
	SRCFILE "IntyMusicCredits.bas",83
	RETURN
	ENDP
	;[84] 
	SRCFILE "IntyMusicCredits.bas",84
	;[85] DrawPiano: PROCEDURE			'- Draw piano, clear bottom lines 1st---
	SRCFILE "IntyMusicCredits.bas",85
	; DRAWPIANO
Q35:	PROC
	BEGIN
	;[86] 	FOR #x=0 TO IntyNote
	SRCFILE "IntyMusicCredits.bas",86
	CLRR R0
	MVO R0,V10
T47:
	;[87] 		#BACKTAB(200+#x)= IntyPiano(#x)		
	SRCFILE "IntyMusicCredits.bas",87
	MVII #Q2,R0
	MVII #200,R1
	ADD V10,R1
	ADDR R1,R0
	MVII #Q42,R3
	ADD V10,R3
	MVI@ R3,R1
	MOVR R0,R4
	MVO@ R1,R4
	;[88] 	NEXT #x		
	SRCFILE "IntyMusicCredits.bas",88
	MVI V10,R0
	INCR R0
	MVO R0,V10
	CMP V6,R0
	BLE T47
	;[89] 	
	SRCFILE "IntyMusicCredits.bas",89
	;[90] 	#BACKTAB(220)=#IntyMusicBlink
	SRCFILE "IntyMusicCredits.bas",90
	MVI V1,R0
	MVO R0,Q2+220
	;[91] 	FOR #x=221 TO 238 
	SRCFILE "IntyMusicCredits.bas",91
	MVII #221,R0
	MVO R0,V10
T48:
	;[92] 		#BACKTAB(#x)= 0
	SRCFILE "IntyMusicCredits.bas",92
	CLRR R0
	MVII #Q2,R3
	ADD V10,R3
	MVO@ R0,R3
	;[93] 	NEXT #x	
	SRCFILE "IntyMusicCredits.bas",93
	MVI V10,R0
	INCR R0
	MVO R0,V10
	CMPI #238,R0
	BLE T48
	;[94] END
	SRCFILE "IntyMusicCredits.bas",94
	RETURN
	ENDP
	;[95] 
	SRCFILE "IntyMusicCredits.bas",95
	;[96] DrawEmptyTopStaff: PROCEDURE
	SRCFILE "IntyMusicCredits.bas",96
	; DRAWEMPTYTOPSTAFF
Q38:	PROC
	BEGIN
	;[97] 	IF INTYMUSIC_FANFOLD THEN #BACKTAB(0)=#IntyMusicBlink
	SRCFILE "IntyMusicCredits.bas",97
	MVII #1,R0
	TSTR R0
	BEQ T49
	MVI V1,R0
	MVO R0,Q2
T49:
	;[98] 	FOR #x=1 TO 19
	SRCFILE "IntyMusicCredits.bas",98
	MVII #1,R0
	MVO R0,V10
T50:
	;[99] 		#BACKTAB(#x)=IntyNoteBlankLine(#x)	+ INTYMUSIC_STAFF_COLOR
	SRCFILE "IntyMusicCredits.bas",99
	MVII #Q29,R3
	ADD V10,R3
	MVI@ R3,R0
	MVII #Q2,R3
	ADD V10,R3
	MVO@ R0,R3
	;[100] 	NEXT #x	
	SRCFILE "IntyMusicCredits.bas",100
	MVI V10,R0
	INCR R0
	MVO R0,V10
	CMPI #19,R0
	BLE T50
	;[101] END
	SRCFILE "IntyMusicCredits.bas",101
	RETURN
	ENDP
	;[102] 
	SRCFILE "IntyMusicCredits.bas",102
	;ENDFILE
	;FILE IntyMusic.bas
	;[47] INCLUDE "IntyMusicData.bas"
	SRCFILE "IntyMusic.bas",47
	;FILE IntyMusicData.bas
	;[1] 'IntyMusic by Marco A. Marrero.  Started on 7/30/2016
	SRCFILE "IntyMusicData.bas",1
	;[2] 'Revision 8/9/2016. Bug: Note G5#? was shown as line, had wrong value in Excel
	SRCFILE "IntyMusicData.bas",2
	;[3] '-------
	SRCFILE "IntyMusicData.bas",3
	;[4] 'IntyBasic notes are values from 1 to 61, C2 to C7. In most of these first value is dummy, notes start from 1-18
	SRCFILE "IntyMusicData.bas",4
	;[5] 
	SRCFILE "IntyMusicData.bas",5
	;[6] '---Note relative position (1-36)... according to note value (1-61). 
	SRCFILE "IntyMusicData.bas",6
	;[7] 'IntyNotePosition:
	SRCFILE "IntyMusicData.bas",7
	;[8] 'DATA 0,1,1,2,2,3,4,4,5,5,6,6,7,8,8,9,9,10,11,11,12,12,13,13,14,15,15,16,16,17,18,18,19,19,20,20,21,22,22,23,23,24,25,25,26,26,27,27,28,29,29,30,30,31,32,32,33,33,34,34,35,36
	SRCFILE "IntyMusicData.bas",8
	;[9] 
	SRCFILE "IntyMusicData.bas",9
	;[10] '---Note relative to screen (1-18). I am using 2 notes per card
	SRCFILE "IntyMusicData.bas",10
	;[11] IntyNoteOnscreen:
	SRCFILE "IntyMusicData.bas",11
	; INTYNOTEONSCREEN
Q30:	;[12] DATA 0,1,1,1,1,2,2,2,3,3,3,3,4,4,4,5,5,5,6,6,6,6,7,7,7,8,8,8,8,9,9,9,10,10,10,10,11,11,11,12,12,12,13,13,13,13,14,14,14,15,15,15,15,16,16,16,17,17,17,17,18,18
	SRCFILE "IntyMusicData.bas",12
	DECLE 0
	DECLE 1
	DECLE 1
	DECLE 1
	DECLE 1
	DECLE 2
	DECLE 2
	DECLE 2
	DECLE 3
	DECLE 3
	DECLE 3
	DECLE 3
	DECLE 4
	DECLE 4
	DECLE 4
	DECLE 5
	DECLE 5
	DECLE 5
	DECLE 6
	DECLE 6
	DECLE 6
	DECLE 6
	DECLE 7
	DECLE 7
	DECLE 7
	DECLE 8
	DECLE 8
	DECLE 8
	DECLE 8
	DECLE 9
	DECLE 9
	DECLE 9
	DECLE 10
	DECLE 10
	DECLE 10
	DECLE 10
	DECLE 11
	DECLE 11
	DECLE 11
	DECLE 12
	DECLE 12
	DECLE 12
	DECLE 13
	DECLE 13
	DECLE 13
	DECLE 13
	DECLE 14
	DECLE 14
	DECLE 14
	DECLE 15
	DECLE 15
	DECLE 15
	DECLE 15
	DECLE 16
	DECLE 16
	DECLE 16
	DECLE 17
	DECLE 17
	DECLE 17
	DECLE 17
	DECLE 18
	DECLE 18
	;[13] 
	SRCFILE "IntyMusicData.bas",13
	;[14] '--Note Alpha/letter... GROM card values. C,D,E,F,G,A or B etc..  no # here
	SRCFILE "IntyMusicData.bas",14
	;[15] IntyNoteLetter:
	SRCFILE "IntyMusicData.bas",15
	; INTYNOTELETTER
Q26:	;[16] DATA 0,280,280,288,288,296,304,304,312,312,264,264,272,280,280,288,288,296,304,304,312,312,264,264,272,280,280,288,288,296,304,304,312,312,264,264,272,280,280,288,288,296,304,304,312,312,264,264,272,280,280,288,288,296,304,304,312,312,264,264,272,280
	SRCFILE "IntyMusicData.bas",16
	DECLE 0
	DECLE 280
	DECLE 280
	DECLE 288
	DECLE 288
	DECLE 296
	DECLE 304
	DECLE 304
	DECLE 312
	DECLE 312
	DECLE 264
	DECLE 264
	DECLE 272
	DECLE 280
	DECLE 280
	DECLE 288
	DECLE 288
	DECLE 296
	DECLE 304
	DECLE 304
	DECLE 312
	DECLE 312
	DECLE 264
	DECLE 264
	DECLE 272
	DECLE 280
	DECLE 280
	DECLE 288
	DECLE 288
	DECLE 296
	DECLE 304
	DECLE 304
	DECLE 312
	DECLE 312
	DECLE 264
	DECLE 264
	DECLE 272
	DECLE 280
	DECLE 280
	DECLE 288
	DECLE 288
	DECLE 296
	DECLE 304
	DECLE 304
	DECLE 312
	DECLE 312
	DECLE 264
	DECLE 264
	DECLE 272
	DECLE 280
	DECLE 280
	DECLE 288
	DECLE 288
	DECLE 296
	DECLE 304
	DECLE 304
	DECLE 312
	DECLE 312
	DECLE 264
	DECLE 264
	DECLE 272
	DECLE 280
	;[17] 
	SRCFILE "IntyMusicData.bas",17
	;[18] '--Sharp notes, according to value. 24=GROM Card #
	SRCFILE "IntyMusicData.bas",18
	;[19] IntyNoteSharp:
	SRCFILE "IntyMusicData.bas",19
	; INTYNOTESHARP
Q27:	;[20] 'DATA " "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," ","#"," ","#"," "," ","#"," ","#"," ","#"," "," "
	SRCFILE "IntyMusicData.bas",20
	;[21] DATA 0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0,0,24,0,24,0,0,24,0,24,0,24,0
	SRCFILE "IntyMusicData.bas",21
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	DECLE 24
	DECLE 0
	;[22] 
	SRCFILE "IntyMusicData.bas",22
	;[23] '--- Ocatave according to note value, =(Octave*8)+(16*8) = GROM card # for 2,3,4,5,6,7
	SRCFILE "IntyMusicData.bas",23
	;[24] IntyNoteOctave:
	SRCFILE "IntyMusicData.bas",24
	; INTYNOTEOCTAVE
Q28:	;[25] DATA 0,144,144,144,144,144,144,144,144,144,144,144,144,152,152,152,152,152,152,152,152,152,152,152,152,160,160,160,160,160,160,160,160,160,160,160,160,168,168,168,168,168,168,168,168,168,168,168,168,176,176,176,176,176,176,176,176,176,176,176,176,184
	SRCFILE "IntyMusicData.bas",25
	DECLE 0
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 144
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 152
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 160
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 168
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 176
	DECLE 184
	;[26] 
	SRCFILE "IntyMusicData.bas",26
	;[27] '--GRAM Card to use------- Positioned horizontally -----
	SRCFILE "IntyMusicData.bas",27
	;[28] 'I combined GRAM cards. 2 notes per card. I wont display adjacent notes, only 1 will be shown
	SRCFILE "IntyMusicData.bas",28
	;[29] IntyNoteGRAM:
	SRCFILE "IntyMusicData.bas",29
	; INTYNOTEGRAM
Q31:	;[30] DATA 0,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2056,2072,2064,2080,2056,2072,2064,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2080,2056,2064,2080,2056,2072,2056,2056,2072,2064,2080,2056,2072,2064,2056,2072,2064,2080,2056,2064,2080,2056,2072,2064,2080,2056,2064
	SRCFILE "IntyMusicData.bas",30
	DECLE 0
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2072
	DECLE 2056
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2072
	DECLE 2064
	DECLE 2080
	DECLE 2056
	DECLE 2064
	;[31] 
	SRCFILE "IntyMusicData.bas",31
	;[32] IntyNoteBlankLine:
	SRCFILE "IntyMusicData.bas",32
	; INTYNOTEBLANKLINE
Q29:	;[33] DATA 2112,2112,2112,2048,2048,2048,2048,2048,2112,2048,2048,2048,2048,2048,2112,2112,2112,2112,2112,2112,2112
	SRCFILE "IntyMusicData.bas",33
	DECLE 2112
	DECLE 2112
	DECLE 2112
	DECLE 2048
	DECLE 2048
	DECLE 2048
	DECLE 2048
	DECLE 2048
	DECLE 2112
	DECLE 2048
	DECLE 2048
	DECLE 2048
	DECLE 2048
	DECLE 2048
	DECLE 2112
	DECLE 2112
	DECLE 2112
	DECLE 2112
	DECLE 2112
	DECLE 2112
	DECLE 2112
	;[34] 
	SRCFILE "IntyMusicData.bas",34
	;[35] '----Piano! GRAM+(Sprite24*8),GRAM+(Sprite25*8), etc-----
	SRCFILE "IntyMusicData.bas",35
	;[36] 'There are 2 1/2 key per GRAM card for the piano, 4 different sprites for hilite. 7 combinations 2 octaves...
	SRCFILE "IntyMusicData.bas",36
	;[37] 'GRAM cards: CD,EF,GA,BC*,DE*,FG*,AB.  (*=same cards as EF,AB,CD)
	SRCFILE "IntyMusicData.bas",37
	;[38] 
	SRCFILE "IntyMusicData.bas",38
	;[39] IntyPiano:
	SRCFILE "IntyMusicData.bas",39
	; INTYPIANO
Q42:	;[40] '2272= Char284 * 8
	SRCFILE "IntyMusicData.bas",40
	;[41] DATA 2272,2208,2192,2200,2192,2296,2208,2296,2208,2192,2200,2192,2296,2208,2296,2208,2192,2200,2192,2296,2208
	SRCFILE "IntyMusicData.bas",41
	DECLE 2272
	DECLE 2208
	DECLE 2192
	DECLE 2200
	DECLE 2192
	DECLE 2296
	DECLE 2208
	DECLE 2296
	DECLE 2208
	DECLE 2192
	DECLE 2200
	DECLE 2192
	DECLE 2296
	DECLE 2208
	DECLE 2296
	DECLE 2208
	DECLE 2192
	DECLE 2200
	DECLE 2192
	DECLE 2296
	DECLE 2208
	;[42] 
	SRCFILE "IntyMusicData.bas",42
	;[43] 'Sprite to show. 1st one is not dummy, but it wont be played. 
	SRCFILE "IntyMusicData.bas",43
	;[44] IntyPianoSprite:
	SRCFILE "IntyMusicData.bas",44
	; INTYPIANOSPRITE
Q33:	;[45] DATA 2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264,2248,2240,2256,2240,2256,2240,2264,2248,2240,2256,2240,2264
	SRCFILE "IntyMusicData.bas",45
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	DECLE 2248
	DECLE 2240
	DECLE 2256
	DECLE 2240
	DECLE 2264
	;[46] 'Its position... on the source spreadsheet its a row of offsets (0-7) + card position (0,8,16,etc)
	SRCFILE "IntyMusicData.bas",46
	;[47] IntyPianoSpriteOffset:
	SRCFILE "IntyMusicData.bas",47
	; INTYPIANOSPRITEOFFSET
Q32:	;[48] DATA 4,0,2,4,6,8,12,14,16,18,20,22,24,28,30,32,34,36,40,42,44,46,48,50,52,56,58,60,62,64,68,70,72,74,76,78,80,84,86,88,90,92,96,98,100,102,104,106,108,112,114,116,118,120,124,126,128,130,132,134,136,140,142,144,146,148,152,154,156
	SRCFILE "IntyMusicData.bas",48
	DECLE 4
	DECLE 0
	DECLE 2
	DECLE 4
	DECLE 6
	DECLE 8
	DECLE 12
	DECLE 14
	DECLE 16
	DECLE 18
	DECLE 20
	DECLE 22
	DECLE 24
	DECLE 28
	DECLE 30
	DECLE 32
	DECLE 34
	DECLE 36
	DECLE 40
	DECLE 42
	DECLE 44
	DECLE 46
	DECLE 48
	DECLE 50
	DECLE 52
	DECLE 56
	DECLE 58
	DECLE 60
	DECLE 62
	DECLE 64
	DECLE 68
	DECLE 70
	DECLE 72
	DECLE 74
	DECLE 76
	DECLE 78
	DECLE 80
	DECLE 84
	DECLE 86
	DECLE 88
	DECLE 90
	DECLE 92
	DECLE 96
	DECLE 98
	DECLE 100
	DECLE 102
	DECLE 104
	DECLE 106
	DECLE 108
	DECLE 112
	DECLE 114
	DECLE 116
	DECLE 118
	DECLE 120
	DECLE 124
	DECLE 126
	DECLE 128
	DECLE 130
	DECLE 132
	DECLE 134
	DECLE 136
	DECLE 140
	DECLE 142
	DECLE 144
	DECLE 146
	DECLE 148
	DECLE 152
	DECLE 154
	DECLE 156
	;[49] 
	SRCFILE "IntyMusicData.bas",49
	;[50] 
	SRCFILE "IntyMusicData.bas",50
	;[51] 
	SRCFILE "IntyMusicData.bas",51
	;[52] 
	SRCFILE "IntyMusicData.bas",52
	;ENDFILE
	;FILE IntyMusic.bas
	;[48] INCLUDE "IntyMusicGraphics.bas"
	SRCFILE "IntyMusic.bas",48
	;FILE IntyMusicGraphics.bas
	;[1] '---- Source: C:\Users\mmarr\GD\Intellivision\IntyMusic5.png
	SRCFILE "IntyMusicGraphics.bas",1
	;[2] ' Wednesday, August 3, 2016
	SRCFILE "IntyMusicGraphics.bas",2
	;[3] ' 
	SRCFILE "IntyMusicGraphics.bas",3
	;[4] 
	SRCFILE "IntyMusicGraphics.bas",4
	;[5] '===MOV:0 == Chr:256===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",5
	;[6] Sprite0:
	SRCFILE "IntyMusicGraphics.bas",6
	; SPRITE0
Q6:	;[7] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",7
	;[8] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",8
	DECLE 16448
	;[9] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",9
	;[10] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",10
	DECLE 16448
	;[11] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",11
	;[12] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",12
	DECLE 16448
	;[13] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",13
	;[14] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",14
	DECLE 16448
	;[15] 
	SRCFILE "IntyMusicGraphics.bas",15
	;[16] '===MOV:1 == Chr:257===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",16
	;[17] 'Sprite1:
	SRCFILE "IntyMusicGraphics.bas",17
	;[18] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",18
	;[19] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",19
	DECLE 20560
	;[20] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",20
	;[21] 	BITMAP ".###...."	'$70
	SRCFILE "IntyMusicGraphics.bas",21
	DECLE 28752
	;[22] 	BITMAP "####...."	'$F0
	SRCFILE "IntyMusicGraphics.bas",22
	;[23] 	BITMAP ".##....."	'$60
	SRCFILE "IntyMusicGraphics.bas",23
	DECLE 24816
	;[24] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",24
	;[25] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",25
	DECLE 16448
	;[26] 
	SRCFILE "IntyMusicGraphics.bas",26
	;[27] '===MOV:2 == Chr:258===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",27
	;[28] 'Sprite2:
	SRCFILE "IntyMusicGraphics.bas",28
	;[29] 	BITMAP ".#....#."	'$42
	SRCFILE "IntyMusicGraphics.bas",29
	;[30] 	BITMAP ".#....#."	'$42
	SRCFILE "IntyMusicGraphics.bas",30
	DECLE 16962
	;[31] 	BITMAP ".#....#."	'$42
	SRCFILE "IntyMusicGraphics.bas",31
	;[32] 	BITMAP ".#..###."	'$4E
	SRCFILE "IntyMusicGraphics.bas",32
	DECLE 20034
	;[33] 	BITMAP ".#.####."	'$5E
	SRCFILE "IntyMusicGraphics.bas",33
	;[34] 	BITMAP ".#..##.."	'$4C
	SRCFILE "IntyMusicGraphics.bas",34
	DECLE 19550
	;[35] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",35
	;[36] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",36
	DECLE 16448
	;[37] 
	SRCFILE "IntyMusicGraphics.bas",37
	;[38] '===MOV:3 == Chr:259===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",38
	;[39] 'Sprite3:
	SRCFILE "IntyMusicGraphics.bas",39
	;[40] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",40
	;[41] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",41
	DECLE 20560
	;[42] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",42
	;[43] 	BITMAP ".###...."	'$70
	SRCFILE "IntyMusicGraphics.bas",43
	DECLE 28752
	;[44] 	BITMAP "####.#.."	'$F4
	SRCFILE "IntyMusicGraphics.bas",44
	;[45] 	BITMAP ".##.#.#."	'$6A
	SRCFILE "IntyMusicGraphics.bas",45
	DECLE 27380
	;[46] 	BITMAP ".#...#.."	'$44
	SRCFILE "IntyMusicGraphics.bas",46
	;[47] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",47
	DECLE 16452
	;[48] 
	SRCFILE "IntyMusicGraphics.bas",48
	;[49] '===MOV:4 == Chr:260===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",49
	;[50] 'Sprite4:
	SRCFILE "IntyMusicGraphics.bas",50
	;[51] 	BITMAP ".#.#..#."	'$52
	SRCFILE "IntyMusicGraphics.bas",51
	;[52] 	BITMAP ".##.#.#."	'$6A
	SRCFILE "IntyMusicGraphics.bas",52
	DECLE 27218
	;[53] 	BITMAP ".#.#..#."	'$52
	SRCFILE "IntyMusicGraphics.bas",53
	;[54] 	BITMAP ".#..###."	'$4E
	SRCFILE "IntyMusicGraphics.bas",54
	DECLE 20050
	;[55] 	BITMAP ".#.####."	'$5E
	SRCFILE "IntyMusicGraphics.bas",55
	;[56] 	BITMAP ".#..##.."	'$4C
	SRCFILE "IntyMusicGraphics.bas",56
	DECLE 19550
	;[57] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",57
	;[58] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",58
	DECLE 16448
	;[59] 
	SRCFILE "IntyMusicGraphics.bas",59
	;[60] '===MOV:5 == Chr:261===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",60
	;[61] 'Sprite5:
	SRCFILE "IntyMusicGraphics.bas",61
	;[62] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",62
	;[63] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",63
	DECLE 0
	;[64] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",64
	;[65] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",65
	DECLE 0
	;[66] 	BITMAP ".##....."	'$60
	SRCFILE "IntyMusicGraphics.bas",66
	;[67] 	BITMAP "#####..."	'$F8
	SRCFILE "IntyMusicGraphics.bas",67
	DECLE 63584
	;[68] 	BITMAP "#..###.."	'$9C
	SRCFILE "IntyMusicGraphics.bas",68
	;[69] 	BITMAP "....###."	'$0E
	SRCFILE "IntyMusicGraphics.bas",69
	DECLE 3740
	;[70] 
	SRCFILE "IntyMusicGraphics.bas",70
	;[71] '===MOV:6 == Chr:262===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",71
	;[72] 'Sprite6:
	SRCFILE "IntyMusicGraphics.bas",72
	;[73] 	BITMAP "......##"	'$03
	SRCFILE "IntyMusicGraphics.bas",73
	;[74] 	BITMAP "......##"	'$03
	SRCFILE "IntyMusicGraphics.bas",74
	DECLE 771
	;[75] 	BITMAP "#...####"	'$8F
	SRCFILE "IntyMusicGraphics.bas",75
	;[76] 	BITMAP "#######."	'$FE
	SRCFILE "IntyMusicGraphics.bas",76
	DECLE 65167
	;[77] 	BITMAP "######.."	'$FC
	SRCFILE "IntyMusicGraphics.bas",77
	;[78] 	BITMAP ".####..."	'$78
	SRCFILE "IntyMusicGraphics.bas",78
	DECLE 30972
	;[79] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",79
	;[80] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",80
	DECLE 0
	;[81] 
	SRCFILE "IntyMusicGraphics.bas",81
	;[82] '===MOV:7 == Chr:263===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",82
	;[83] 'Sprite7:
	SRCFILE "IntyMusicGraphics.bas",83
	;[84] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",84
	;[85] 	BITMAP "..###..."	'$38
	SRCFILE "IntyMusicGraphics.bas",85
	DECLE 14336
	;[86] 	BITMAP "######.."	'$FC
	SRCFILE "IntyMusicGraphics.bas",86
	;[87] 	BITMAP "#######."	'$FE
	SRCFILE "IntyMusicGraphics.bas",87
	DECLE 65276
	;[88] 	BITMAP "###..##."	'$E6
	SRCFILE "IntyMusicGraphics.bas",88
	;[89] 	BITMAP "##...###"	'$C7
	SRCFILE "IntyMusicGraphics.bas",89
	DECLE 51174
	;[90] 	BITMAP "##....##"	'$C3
	SRCFILE "IntyMusicGraphics.bas",90
	;[91] 	BITMAP "#.....##"	'$83
	SRCFILE "IntyMusicGraphics.bas",91
	DECLE 33731
	;[92] 
	SRCFILE "IntyMusicGraphics.bas",92
	;[93] '===MOV:8 == Chr:264===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",93
	;[94] 'Sprite8:
	SRCFILE "IntyMusicGraphics.bas",94
	;[95] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",95
	;[96] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",96
	DECLE 0
	;[97] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",97
	;[98] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",98
	DECLE 0
	;[99] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",99
	;[100] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",100
	DECLE 0
	;[101] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",101
	;[102] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",102
	DECLE 0
	;[103] 
	SRCFILE "IntyMusicGraphics.bas",103
	;[104] '===MOV:9 == Chr:265===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",104
	;[105] 'Sprite9:
	SRCFILE "IntyMusicGraphics.bas",105
	;[106] 	BITMAP "...#...."	'$10
	SRCFILE "IntyMusicGraphics.bas",106
	;[107] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",107
	DECLE 20496
	;[108] 	BITMAP "...#...."	'$10
	SRCFILE "IntyMusicGraphics.bas",108
	;[109] 	BITMAP ".###...."	'$70
	SRCFILE "IntyMusicGraphics.bas",109
	DECLE 28688
	;[110] 	BITMAP "####...."	'$F0
	SRCFILE "IntyMusicGraphics.bas",110
	;[111] 	BITMAP ".##....."	'$60
	SRCFILE "IntyMusicGraphics.bas",111
	DECLE 24816
	;[112] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",112
	;[113] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",113
	DECLE 16384
	;[114] 
	SRCFILE "IntyMusicGraphics.bas",114
	;[115] '===MOV:10 == Chr:266===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",115
	;[116] 'Sprite10:
	SRCFILE "IntyMusicGraphics.bas",116
	;[117] 	BITMAP "......#."	'$02
	SRCFILE "IntyMusicGraphics.bas",117
	;[118] 	BITMAP "......#."	'$02
	SRCFILE "IntyMusicGraphics.bas",118
	DECLE 514
	;[119] 	BITMAP "......#."	'$02
	SRCFILE "IntyMusicGraphics.bas",119
	;[120] 	BITMAP "....###."	'$0E
	SRCFILE "IntyMusicGraphics.bas",120
	DECLE 3586
	;[121] 	BITMAP "...####."	'$1E
	SRCFILE "IntyMusicGraphics.bas",121
	;[122] 	BITMAP "....##.."	'$0C
	SRCFILE "IntyMusicGraphics.bas",122
	DECLE 3102
	;[123] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",123
	;[124] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",124
	DECLE 0
	;[125] 
	SRCFILE "IntyMusicGraphics.bas",125
	;[126] '===MOV:11 == Chr:267===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",126
	;[127] 'Sprite11:
	SRCFILE "IntyMusicGraphics.bas",127
	;[128] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",128
	;[129] 	BITMAP ".....#.."	'$04
	SRCFILE "IntyMusicGraphics.bas",129
	DECLE 1088
	;[130] 	BITMAP ".##.#.#."	'$6A
	SRCFILE "IntyMusicGraphics.bas",130
	;[131] 	BITMAP "####.#.."	'$F4
	SRCFILE "IntyMusicGraphics.bas",131
	DECLE 62570
	;[132] 	BITMAP ".###...."	'$70
	SRCFILE "IntyMusicGraphics.bas",132
	;[133] 	BITMAP "...#...."	'$10
	SRCFILE "IntyMusicGraphics.bas",133
	DECLE 4208
	;[134] 	BITMAP ".#.#...."	'$50
	SRCFILE "IntyMusicGraphics.bas",134
	;[135] 	BITMAP "...#...."	'$10
	SRCFILE "IntyMusicGraphics.bas",135
	DECLE 4176
	;[136] 
	SRCFILE "IntyMusicGraphics.bas",136
	;[137] '===MOV:12 == Chr:268===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",137
	;[138] 'Sprite12:
	SRCFILE "IntyMusicGraphics.bas",138
	;[139] 	BITMAP "..#...#."	'$22
	SRCFILE "IntyMusicGraphics.bas",139
	;[140] 	BITMAP ".#.#..#."	'$52
	SRCFILE "IntyMusicGraphics.bas",140
	DECLE 21026
	;[141] 	BITMAP "..#...#."	'$22
	SRCFILE "IntyMusicGraphics.bas",141
	;[142] 	BITMAP "....###."	'$0E
	SRCFILE "IntyMusicGraphics.bas",142
	DECLE 3618
	;[143] 	BITMAP "...####."	'$1E
	SRCFILE "IntyMusicGraphics.bas",143
	;[144] 	BITMAP "....##.."	'$0C
	SRCFILE "IntyMusicGraphics.bas",144
	DECLE 3102
	;[145] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",145
	;[146] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",146
	DECLE 0
	;[147] 
	SRCFILE "IntyMusicGraphics.bas",147
	;[148] '===MOV:13 == Chr:269===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",148
	;[149] 'Sprite13:
	SRCFILE "IntyMusicGraphics.bas",149
	;[150] 	BITMAP "...#####"	'$1F
	SRCFILE "IntyMusicGraphics.bas",150
	;[151] 	BITMAP ".#######"	'$7F
	SRCFILE "IntyMusicGraphics.bas",151
	DECLE 32543
	;[152] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",152
	;[153] 	BITMAP "#......."	'$80
	SRCFILE "IntyMusicGraphics.bas",153
	DECLE 32992
	;[154] 	BITMAP "...##..."	'$18
	SRCFILE "IntyMusicGraphics.bas",154
	;[155] 	BITMAP "..####.."	'$3C
	SRCFILE "IntyMusicGraphics.bas",155
	DECLE 15384
	;[156] 	BITMAP ".##.###."	'$6E
	SRCFILE "IntyMusicGraphics.bas",156
	;[157] 	BITMAP ".#..####"	'$4F
	SRCFILE "IntyMusicGraphics.bas",157
	DECLE 20334
	;[158] 
	SRCFILE "IntyMusicGraphics.bas",158
	;[159] '===MOV:14 == Chr:270===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",159
	;[160] 'Sprite14:
	SRCFILE "IntyMusicGraphics.bas",160
	;[161] 	BITMAP "...#####"	'$1F
	SRCFILE "IntyMusicGraphics.bas",161
	;[162] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",162
	DECLE 65311
	;[163] 	BITMAP "####.##."	'$F6
	SRCFILE "IntyMusicGraphics.bas",163
	;[164] 	BITMAP "#....##."	'$86
	SRCFILE "IntyMusicGraphics.bas",164
	DECLE 34550
	;[165] 	BITMAP "##..##.."	'$CC
	SRCFILE "IntyMusicGraphics.bas",165
	;[166] 	BITMAP "#####..."	'$F8
	SRCFILE "IntyMusicGraphics.bas",166
	DECLE 63692
	;[167] 	BITMAP ".###...."	'$70
	SRCFILE "IntyMusicGraphics.bas",167
	;[168] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",168
	DECLE 112
	;[169] 
	SRCFILE "IntyMusicGraphics.bas",169
	;[170] '===MOV:15 == Chr:271===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",170
	;[171] 'Sprite15:
	SRCFILE "IntyMusicGraphics.bas",171
	;[172] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",172
	;[173] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",173
	DECLE 0
	;[174] 	BITMAP "#......."	'$80
	SRCFILE "IntyMusicGraphics.bas",174
	;[175] 	BITMAP "#......#"	'$81
	SRCFILE "IntyMusicGraphics.bas",175
	DECLE 33152
	;[176] 	BITMAP "##....##"	'$C3
	SRCFILE "IntyMusicGraphics.bas",176
	;[177] 	BITMAP ".##...##"	'$63
	SRCFILE "IntyMusicGraphics.bas",177
	DECLE 25539
	;[178] 	BITMAP "..##..##"	'$33
	SRCFILE "IntyMusicGraphics.bas",178
	;[179] 	BITMAP "...##..#"	'$19
	SRCFILE "IntyMusicGraphics.bas",179
	DECLE 6451
	;[180] 
	SRCFILE "IntyMusicGraphics.bas",180
	;[181] '===MOV:16 == Chr:272===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",181
	;[182] Sprite16:
	SRCFILE "IntyMusicGraphics.bas",182
	; SPRITE16
Q7:	;[183] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",183
	;[184] 	BITMAP "#......."	'$80
	SRCFILE "IntyMusicGraphics.bas",184
	DECLE 32768
	;[185] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",185
	;[186] 	BITMAP ".###...."	'$70
	SRCFILE "IntyMusicGraphics.bas",186
	DECLE 28896
	;[187] 	BITMAP "..###..."	'$38
	SRCFILE "IntyMusicGraphics.bas",187
	;[188] 	BITMAP "...###.#"	'$1D
	SRCFILE "IntyMusicGraphics.bas",188
	DECLE 7480
	;[189] 	BITMAP ".#######"	'$7F
	SRCFILE "IntyMusicGraphics.bas",189
	;[190] 	BITMAP "#######."	'$FE
	SRCFILE "IntyMusicGraphics.bas",190
	DECLE 65151
	;[191] 
	SRCFILE "IntyMusicGraphics.bas",191
	;[192] '===MOV:17 == Chr:273===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",192
	;[193] 'Sprite17:
	SRCFILE "IntyMusicGraphics.bas",193
	;[194] 	BITMAP "...###.."	'$1C
	SRCFILE "IntyMusicGraphics.bas",194
	;[195] 	BITMAP "....###."	'$0E
	SRCFILE "IntyMusicGraphics.bas",195
	DECLE 3612
	;[196] 	BITMAP ".....###"	'$07
	SRCFILE "IntyMusicGraphics.bas",196
	;[197] 	BITMAP "......##"	'$03
	SRCFILE "IntyMusicGraphics.bas",197
	DECLE 775
	;[198] 	BITMAP ".......#"	'$01
	SRCFILE "IntyMusicGraphics.bas",198
	;[199] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",199
	DECLE 1
	;[200] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",200
	;[201] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",201
	DECLE 0
	;[202] 
	SRCFILE "IntyMusicGraphics.bas",202
	;[203] '===MOV:18 == Chr:274===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",203
	;[204] 'Sprite18:
	SRCFILE "IntyMusicGraphics.bas",204
	;[205] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",205
	;[206] 	BITMAP "#..#..##"	'$93
	SRCFILE "IntyMusicGraphics.bas",206
	DECLE 37887
	;[207] 	BITMAP "#..#..##"	'$93
	SRCFILE "IntyMusicGraphics.bas",207
	;[208] 	BITMAP "#..#..##"	'$93
	SRCFILE "IntyMusicGraphics.bas",208
	DECLE 37779
	;[209] 	BITMAP "#..#..##"	'$93
	SRCFILE "IntyMusicGraphics.bas",209
	;[210] 	BITMAP "...#...#"	'$11
	SRCFILE "IntyMusicGraphics.bas",210
	DECLE 4499
	;[211] 	BITMAP "...#...#"	'$11
	SRCFILE "IntyMusicGraphics.bas",211
	;[212] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",212
	DECLE 65297
	;[213] 
	SRCFILE "IntyMusicGraphics.bas",213
	;[214] '===MOV:19 == Chr:275===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",214
	;[215] 'Sprite19:
	SRCFILE "IntyMusicGraphics.bas",215
	;[216] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",216
	;[217] 	BITMAP "#.###.##"	'$BB
	SRCFILE "IntyMusicGraphics.bas",217
	DECLE 48127
	;[218] 	BITMAP "#.###.##"	'$BB
	SRCFILE "IntyMusicGraphics.bas",218
	;[219] 	BITMAP "#.###.##"	'$BB
	SRCFILE "IntyMusicGraphics.bas",219
	DECLE 48059
	;[220] 	BITMAP "#.###.##"	'$BB
	SRCFILE "IntyMusicGraphics.bas",220
	;[221] 	BITMAP "...#...#"	'$11
	SRCFILE "IntyMusicGraphics.bas",221
	DECLE 4539
	;[222] 	BITMAP "...#...#"	'$11
	SRCFILE "IntyMusicGraphics.bas",222
	;[223] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",223
	DECLE 65297
	;[224] 
	SRCFILE "IntyMusicGraphics.bas",224
	;[225] '===MOV:20 == Chr:276===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",225
	;[226] 'Sprite20:
	SRCFILE "IntyMusicGraphics.bas",226
	;[227] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",227
	;[228] 	BITMAP "..###.##"	'$3B
	SRCFILE "IntyMusicGraphics.bas",228
	DECLE 15359
	;[229] 	BITMAP "..###.##"	'$3B
	SRCFILE "IntyMusicGraphics.bas",229
	;[230] 	BITMAP "..###.##"	'$3B
	SRCFILE "IntyMusicGraphics.bas",230
	DECLE 15163
	;[231] 	BITMAP "..###.##"	'$3B
	SRCFILE "IntyMusicGraphics.bas",231
	;[232] 	BITMAP "...#...#"	'$11
	SRCFILE "IntyMusicGraphics.bas",232
	DECLE 4411
	;[233] 	BITMAP "...#...#"	'$11
	SRCFILE "IntyMusicGraphics.bas",233
	;[234] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",234
	DECLE 65297
	;[235] 
	SRCFILE "IntyMusicGraphics.bas",235
	;[236] '===MOV:21 == Chr:277===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",236
	;[237] 'Sprite21:
	SRCFILE "IntyMusicGraphics.bas",237
	;[238] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",238
	;[239] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",239
	DECLE 0
	;[240] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",240
	;[241] 	BITMAP ".......#"	'$01
	SRCFILE "IntyMusicGraphics.bas",241
	DECLE 256
	;[242] 	BITMAP "..##...#"	'$31
	SRCFILE "IntyMusicGraphics.bas",242
	;[243] 	BITMAP ".####.##"	'$7B
	SRCFILE "IntyMusicGraphics.bas",243
	DECLE 31537
	;[244] 	BITMAP "#####.#."	'$FA
	SRCFILE "IntyMusicGraphics.bas",244
	;[245] 	BITMAP "#####.#."	'$FA
	SRCFILE "IntyMusicGraphics.bas",245
	DECLE 64250
	;[246] 
	SRCFILE "IntyMusicGraphics.bas",246
	;[247] '===MOV:22 == Chr:278===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",247
	;[248] 'Sprite22:
	SRCFILE "IntyMusicGraphics.bas",248
	;[249] 	BITMAP "#.##..#."	'$B2
	SRCFILE "IntyMusicGraphics.bas",249
	;[250] 	BITMAP "##...###"	'$C7
	SRCFILE "IntyMusicGraphics.bas",250
	DECLE 51122
	;[251] 	BITMAP ".#######"	'$7F
	SRCFILE "IntyMusicGraphics.bas",251
	;[252] 	BITMAP "..######"	'$3F
	SRCFILE "IntyMusicGraphics.bas",252
	DECLE 16255
	;[253] 	BITMAP ".......#"	'$01
	SRCFILE "IntyMusicGraphics.bas",253
	;[254] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",254
	DECLE 1
	;[255] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",255
	;[256] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",256
	DECLE 0
	;[257] 
	SRCFILE "IntyMusicGraphics.bas",257
	;[258] '===MOV:23 == Chr:279===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",258
	;[259] 'Sprite23:
	SRCFILE "IntyMusicGraphics.bas",259
	;[260] 	BITMAP "###..###"	'$E7
	SRCFILE "IntyMusicGraphics.bas",260
	;[261] 	BITMAP "###..###"	'$E7
	SRCFILE "IntyMusicGraphics.bas",261
	DECLE 59367
	;[262] 	BITMAP "###..###"	'$E7
	SRCFILE "IntyMusicGraphics.bas",262
	;[263] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",263
	DECLE 231
	;[264] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",264
	;[265] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",265
	DECLE 0
	;[266] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",266
	;[267] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",267
	DECLE 0
	;[268] 
	SRCFILE "IntyMusicGraphics.bas",268
	;[269] '===MOV:24 == Chr:280===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",269
	;[270] 'Sprite24:
	SRCFILE "IntyMusicGraphics.bas",270
	;[271] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",271
	;[272] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",272
	DECLE 57344
	;[273] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",273
	;[274] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",274
	DECLE 57568
	;[275] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",275
	;[276] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",276
	DECLE 224
	;[277] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",277
	;[278] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",278
	DECLE 0
	;[279] 
	SRCFILE "IntyMusicGraphics.bas",279
	;[280] '===MOV:25 == Chr:281===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",280
	;[281] 'Sprite25:
	SRCFILE "IntyMusicGraphics.bas",281
	;[282] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",282
	;[283] 	BITMAP "##......"	'$C0
	SRCFILE "IntyMusicGraphics.bas",283
	DECLE 49152
	;[284] 	BITMAP "##......"	'$C0
	SRCFILE "IntyMusicGraphics.bas",284
	;[285] 	BITMAP "##......"	'$C0
	SRCFILE "IntyMusicGraphics.bas",285
	DECLE 49344
	;[286] 	BITMAP "##......"	'$C0
	SRCFILE "IntyMusicGraphics.bas",286
	;[287] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",287
	DECLE 57536
	;[288] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",288
	;[289] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",289
	DECLE 224
	;[290] 
	SRCFILE "IntyMusicGraphics.bas",290
	;[291] '===MOV:26 == Chr:282===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",291
	;[292] 'Sprite26:
	SRCFILE "IntyMusicGraphics.bas",292
	;[293] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",293
	;[294] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",294
	DECLE 16384
	;[295] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",295
	;[296] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",296
	DECLE 16448
	;[297] 	BITMAP ".#......"	'$40
	SRCFILE "IntyMusicGraphics.bas",297
	;[298] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",298
	DECLE 57408
	;[299] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",299
	;[300] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",300
	DECLE 224
	;[301] 
	SRCFILE "IntyMusicGraphics.bas",301
	;[302] '===MOV:27 == Chr:283===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",302
	;[303] 'Sprite27:
	SRCFILE "IntyMusicGraphics.bas",303
	;[304] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",304
	;[305] 	BITMAP ".##....."	'$60
	SRCFILE "IntyMusicGraphics.bas",305
	DECLE 24576
	;[306] 	BITMAP ".##....."	'$60
	SRCFILE "IntyMusicGraphics.bas",306
	;[307] 	BITMAP ".##....."	'$60
	SRCFILE "IntyMusicGraphics.bas",307
	DECLE 24672
	;[308] 	BITMAP ".##....."	'$60
	SRCFILE "IntyMusicGraphics.bas",308
	;[309] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",309
	DECLE 57440
	;[310] 	BITMAP "###....."	'$E0
	SRCFILE "IntyMusicGraphics.bas",310
	;[311] 	BITMAP "........"	'$00
	SRCFILE "IntyMusicGraphics.bas",311
	DECLE 224
	;[312] 
	SRCFILE "IntyMusicGraphics.bas",312
	;[313] '===MOV:28 == Chr:284===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",313
	;[314] 'Sprite28:
	SRCFILE "IntyMusicGraphics.bas",314
	;[315] 	BITMAP "########"	
	SRCFILE "IntyMusicGraphics.bas",315
	;[316] 	BITMAP "####...#"	
	SRCFILE "IntyMusicGraphics.bas",316
	DECLE 61951
	;[317] 	BITMAP "####...#"	
	SRCFILE "IntyMusicGraphics.bas",317
	;[318] 	BITMAP "####...#"	
	SRCFILE "IntyMusicGraphics.bas",318
	DECLE 61937
	;[319] 	BITMAP "####...#"	
	SRCFILE "IntyMusicGraphics.bas",319
	;[320] 	BITMAP "####...#"
	SRCFILE "IntyMusicGraphics.bas",320
	DECLE 61937
	;[321] 	BITMAP "####...#"
	SRCFILE "IntyMusicGraphics.bas",321
	;[322] 	BITMAP "########"	
	SRCFILE "IntyMusicGraphics.bas",322
	DECLE 65521
	;[323] 
	SRCFILE "IntyMusicGraphics.bas",323
	;[324] '===MOV:29 == Chr:285===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",324
	;[325] 'Sprite29:
	SRCFILE "IntyMusicGraphics.bas",325
	;[326] 	BITMAP "....#..."	'$08
	SRCFILE "IntyMusicGraphics.bas",326
	;[327] 	BITMAP "....##.."	'$0C
	SRCFILE "IntyMusicGraphics.bas",327
	DECLE 3080
	;[328] 	BITMAP "....###."	'$0E
	SRCFILE "IntyMusicGraphics.bas",328
	;[329] 	BITMAP "....#.#."	'$0A
	SRCFILE "IntyMusicGraphics.bas",329
	DECLE 2574
	;[330] 	BITMAP "....#.#."	'$0A
	SRCFILE "IntyMusicGraphics.bas",330
	;[331] 	BITMAP "..###..."	'$38
	SRCFILE "IntyMusicGraphics.bas",331
	DECLE 14346
	;[332] 	BITMAP ".####..."		'$78
	SRCFILE "IntyMusicGraphics.bas",332
	;[333] 	BITMAP "..##...."	'$30
	SRCFILE "IntyMusicGraphics.bas",333
	DECLE 12408
	;[334] 
	SRCFILE "IntyMusicGraphics.bas",334
	;[335] '===MOV:30 == Chr:286===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",335
	;[336] 'Sprite30:
	SRCFILE "IntyMusicGraphics.bas",336
	;[337] 	BITMAP "...#...."
	SRCFILE "IntyMusicGraphics.bas",337
	;[338] 	BITMAP "...##..."
	SRCFILE "IntyMusicGraphics.bas",338
	DECLE 6160
	;[339] 	BITMAP "...###.."
	SRCFILE "IntyMusicGraphics.bas",339
	;[340] 	BITMAP "...#.#.."
	SRCFILE "IntyMusicGraphics.bas",340
	DECLE 5148
	;[341] 	BITMAP "...#.#.."
	SRCFILE "IntyMusicGraphics.bas",341
	;[342] 	BITMAP ".###...."
	SRCFILE "IntyMusicGraphics.bas",342
	DECLE 28692
	;[343] 	BITMAP "####...."
	SRCFILE "IntyMusicGraphics.bas",343
	;[344] 	BITMAP ".##....."
	SRCFILE "IntyMusicGraphics.bas",344
	DECLE 24816
	;[345] 
	SRCFILE "IntyMusicGraphics.bas",345
	;[346] '===MOV:31 == Chr:287===== [8,8]
	SRCFILE "IntyMusicGraphics.bas",346
	;[347] 'Sprite31:
	SRCFILE "IntyMusicGraphics.bas",347
	;[348] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",348
	;[349] 	BITMAP "#.###..#"	'$B9
	SRCFILE "IntyMusicGraphics.bas",349
	DECLE 47615
	;[350] 	BITMAP "#.###. #"	'$B9
	SRCFILE "IntyMusicGraphics.bas",350
	;[351] 	BITMAP "#.###..#"	'$B9
	SRCFILE "IntyMusicGraphics.bas",351
	DECLE 47545
	;[352] 	BITMAP "#.###. #"	'$B9
	SRCFILE "IntyMusicGraphics.bas",352
	;[353] 	BITMAP "...#...#"	'$11
	SRCFILE "IntyMusicGraphics.bas",353
	DECLE 4537
	;[354] 	BITMAP "...#.. #"	'$11
	SRCFILE "IntyMusicGraphics.bas",354
	;[355] 	BITMAP "########"	'$FF
	SRCFILE "IntyMusicGraphics.bas",355
	DECLE 65297
	;[356] 
	SRCFILE "IntyMusicGraphics.bas",356
	;[357] 
	SRCFILE "IntyMusicGraphics.bas",357
	;[358] '//Total of 32 characters.
	SRCFILE "IntyMusicGraphics.bas",358
	;ENDFILE
	;FILE IntyMusic.bas
	;[49] 
	SRCFILE "IntyMusic.bas",49
	;[50] '========================== Options #2 - More customization ========================================
	SRCFILE "IntyMusic.bas",50
	;[51] 
	SRCFILE "IntyMusic.bas",51
	;[52] IntyMusicInit_Credits: PROCEDURE
	SRCFILE "IntyMusic.bas",52
	; INTYMUSICINIT_CREDITS
Q36:	PROC
	BEGIN
	;[53] 	'---------------- ADD INFORMATION BELOW -------------------------
	SRCFILE "IntyMusic.bas",53
	;[54] 	'--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
	SRCFILE "IntyMusic.bas",54
	;[55] 	PRINT COLOR FG_DARKGREEN
	SRCFILE "IntyMusic.bas",55
	MVII #4,R0
	MVO R0,_color
	;[56] 	'20 char max 1234567890123456789
	SRCFILE "IntyMusic.bas",56
	;[57] 	PRINT AT 060,"---Space Harrier---"	
	SRCFILE "IntyMusic.bas",57
	MVII #572,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #104,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #496,R0
	MVO@ R0,R4
	XORI #792,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #552,R0
	MVO@ R0,R4
	XORI #320,R0
	MVO@ R0,R4
	XORI #840,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #760,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[58] 	
	SRCFILE "IntyMusic.bas",58
	;[59] 	PRINT COLOR FG_GREEN
	SRCFILE "IntyMusic.bas",59
	MVII #5,R0
	MVO R0,_color
	;[60] 	PRINT AT 080,"Bach prelude-BWV 847"
	SRCFILE "IntyMusic.bas",60
	MVII #592,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #272,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #792,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #576,R0
	MVO@ R0,R4
	XORI #640,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #200,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #576,R0
	MVO@ R0,R4
	XORI #376,R0
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #432,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[61] 	PRINT AT 100,"  by Mark Cooksey  "	
	SRCFILE "IntyMusic.bas",61
	MVII #612,R0
	MVO R0,_screen
	MOVR R0,R4
	MVI _color,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #528,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #712,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #200,R0
	MVO@ R0,R4
	XORI #600,R0
	MVO@ R0,R4
	XORI #280,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #712,R0
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[62] 	PRINT AT 120,"for the Commodore 64"
	SRCFILE "IntyMusic.bas",62
	MVII #632,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #560,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #656,R0
	MVO@ R0,R4
	XORI #672,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #552,R0
	MVO@ R0,R4
	XORI #280,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #552,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[63] 	'-----------------------------------------------------------------
	SRCFILE "IntyMusic.bas",63
	;[64] END	
	SRCFILE "IntyMusic.bas",64
	RETURN
	ENDP
	;[65] 
	SRCFILE "IntyMusic.bas",65
	;[66] '-----Music to use------
	SRCFILE "IntyMusic.bas",66
	;[67] 'MyMusic:
	SRCFILE "IntyMusic.bas",67
	;[68] asm org $A000
	SRCFILE "IntyMusic.bas",68
 org $A000
	;[69] INCLUDE "Songs\SHarrierC64.bas"		 '<---- Music data. Data label *must* be named "MyMusic"
	SRCFILE "IntyMusic.bas",69
	;FILE Songs\SHarrierC64.bas
	;[1] 'Space Harrier C64 hi-score, source file:MIDI
	SRCFILE "Songs\SHarrierC64.bas",1
	;[2] 'Arrangement of Bach prelude, BWV 847, Prelude No. 2 in C Minor book 1 of The Well-Tempered Clavie
	SRCFILE "Songs\SHarrierC64.bas",2
	;[3] 'by Mark Cooksey
	SRCFILE "Songs\SHarrierC64.bas",3
	;[4] '
	SRCFILE "Songs\SHarrierC64.bas",4
	;[5] MyMusic:
	SRCFILE "Songs\SHarrierC64.bas",5
	; MYMUSIC
Q17:	;[6] DATA 2
	SRCFILE "Songs\SHarrierC64.bas",6
	DECLE 2
	;[7] 
	SRCFILE "Songs\SHarrierC64.bas",7
	;[8] MUSIC E3,G4,B4
	SRCFILE "Songs\SHarrierC64.bas",8
	DECLE 8209,36
	;[9] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",9
	DECLE 16191,63
	;[10] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",10
	DECLE 16191,63
	;[11] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",11
	DECLE 16191,63
	;[12] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",12
	DECLE 16191,63
	;[13] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",13
	DECLE 16191,63
	;[14] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",14
	DECLE 16191,63
	;[15] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",15
	DECLE 16191,63
	;[16] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",16
	DECLE 16191,63
	;[17] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",17
	DECLE 16191,63
	;[18] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",18
	DECLE 16191,63
	;[19] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",19
	DECLE 16191,63
	;[20] MUSIC G3,s,D5
	SRCFILE "Songs\SHarrierC64.bas",20
	DECLE 16148,39
	;[21] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",21
	DECLE 16191,63
	;[22] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",22
	DECLE 16191,63
	;[23] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",23
	DECLE 16191,63
	;[24] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",24
	DECLE 6975,35
	;[25] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",25
	DECLE 16191,63
	;[26] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",26
	DECLE 16191,63
	;[27] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",27
	DECLE 16191,63
	;[28] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",28
	DECLE 6463,34
	;[29] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",29
	DECLE 16191,63
	;[30] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",30
	DECLE 16191,63
	;[31] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",31
	DECLE 16191,63
	;[32] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",32
	DECLE 6975,35
	;[33] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",33
	DECLE 16191,63
	;[34] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",34
	DECLE 16191,63
	;[35] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",35
	DECLE 16191,63
	;[36] MUSIC A3#,s,G4
	SRCFILE "Songs\SHarrierC64.bas",36
	DECLE 16151,32
	;[37] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",37
	DECLE 16191,63
	;[38] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",38
	DECLE 16191,63
	;[39] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",39
	DECLE 16191,63
	;[40] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",40
	DECLE 6975,35
	;[41] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",41
	DECLE 16191,63
	;[42] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",42
	DECLE 16191,63
	;[43] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",43
	DECLE 16191,63
	;[44] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",44
	DECLE 6463,34
	;[45] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",45
	DECLE 16191,63
	;[46] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",46
	DECLE 16191,63
	;[47] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",47
	DECLE 16191,63
	;[48] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",48
	DECLE 6975,35
	;[49] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",49
	DECLE 16191,63
	;[50] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",50
	DECLE 16191,63
	;[51] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",51
	DECLE 16191,63
	;[52] MUSIC G3,s,D5
	SRCFILE "Songs\SHarrierC64.bas",52
	DECLE 16148,39
	;[53] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",53
	DECLE 16191,63
	;[54] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",54
	DECLE 16191,63
	;[55] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",55
	DECLE 16191,63
	;[56] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",56
	DECLE 6975,35
	;[57] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",57
	DECLE 16191,63
	;[58] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",58
	DECLE 16191,63
	;[59] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",59
	DECLE 16191,63
	;[60] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",60
	DECLE 6463,34
	;[61] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",61
	DECLE 16191,63
	;[62] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",62
	DECLE 16191,63
	;[63] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",63
	DECLE 16191,63
	;[64] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",64
	DECLE 6975,35
	;[65] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",65
	DECLE 16191,63
	;[66] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",66
	DECLE 16191,63
	;[67] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",67
	DECLE 16191,63
	;[68] MUSIC A3#,s,G4
	SRCFILE "Songs\SHarrierC64.bas",68
	DECLE 16151,32
	;[69] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",69
	DECLE 16191,63
	;[70] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",70
	DECLE 16191,63
	;[71] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",71
	DECLE 16191,63
	;[72] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",72
	DECLE 6975,35
	;[73] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",73
	DECLE 16191,63
	;[74] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",74
	DECLE 16191,63
	;[75] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",75
	DECLE 16191,63
	;[76] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",76
	DECLE 6463,34
	;[77] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",77
	DECLE 16191,63
	;[78] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",78
	DECLE 16191,63
	;[79] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",79
	DECLE 16191,63
	;[80] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",80
	DECLE 6975,35
	;[81] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",81
	DECLE 16191,63
	;[82] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",82
	DECLE 16191,63
	;[83] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",83
	DECLE 16191,63
	;[84] MUSIC G3,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",84
	DECLE 16148,40
	;[85] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",85
	DECLE 16191,63
	;[86] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",86
	DECLE 16191,63
	;[87] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",87
	DECLE 16191,63
	;[88] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",88
	DECLE 7231,37
	;[89] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",89
	DECLE 16191,63
	;[90] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",90
	DECLE 16191,63
	;[91] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",91
	DECLE 16191,63
	;[92] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",92
	DECLE 6975,36
	;[93] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",93
	DECLE 16191,63
	;[94] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",94
	DECLE 16191,63
	;[95] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",95
	DECLE 16191,63
	;[96] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",96
	DECLE 7231,37
	;[97] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",97
	DECLE 16191,63
	;[98] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",98
	DECLE 16191,63
	;[99] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",99
	DECLE 16191,63
	;[100] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",100
	DECLE 6463,32
	;[101] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",101
	DECLE 16191,63
	;[102] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",102
	DECLE 16191,63
	;[103] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",103
	DECLE 16191,63
	;[104] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",104
	DECLE 7231,37
	;[105] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",105
	DECLE 16191,63
	;[106] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",106
	DECLE 16191,63
	;[107] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",107
	DECLE 16191,63
	;[108] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",108
	DECLE 6975,36
	;[109] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",109
	DECLE 16191,63
	;[110] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",110
	DECLE 16191,63
	;[111] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",111
	DECLE 16191,63
	;[112] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",112
	DECLE 7231,37
	;[113] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",113
	DECLE 16191,63
	;[114] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",114
	DECLE 16191,63
	;[115] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",115
	DECLE 16191,63
	;[116] MUSIC G3,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",116
	DECLE 16148,40
	;[117] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",117
	DECLE 16191,63
	;[118] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",118
	DECLE 16191,63
	;[119] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",119
	DECLE 16191,63
	;[120] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",120
	DECLE 7231,37
	;[121] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",121
	DECLE 16191,63
	;[122] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",122
	DECLE 16191,63
	;[123] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",123
	DECLE 16191,63
	;[124] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",124
	DECLE 6975,36
	;[125] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",125
	DECLE 16191,63
	;[126] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",126
	DECLE 16191,63
	;[127] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",127
	DECLE 16191,63
	;[128] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",128
	DECLE 7231,37
	;[129] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",129
	DECLE 16191,63
	;[130] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",130
	DECLE 16191,63
	;[131] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",131
	DECLE 16191,63
	;[132] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",132
	DECLE 6463,32
	;[133] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",133
	DECLE 16191,63
	;[134] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",134
	DECLE 16191,63
	;[135] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",135
	DECLE 16191,63
	;[136] 
	SRCFILE "Songs\SHarrierC64.bas",136
	;[137] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",137
	DECLE 7231,37
	;[138] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",138
	DECLE 16191,63
	;[139] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",139
	DECLE 16191,63
	;[140] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",140
	DECLE 16191,63
	;[141] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",141
	DECLE 6975,36
	;[142] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",142
	DECLE 16191,63
	;[143] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",143
	DECLE 16191,63
	;[144] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",144
	DECLE 16191,63
	;[145] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",145
	DECLE 7231,37
	;[146] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",146
	DECLE 16191,63
	;[147] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",147
	DECLE 16191,63
	;[148] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",148
	DECLE 16191,63
	;[149] MUSIC F3#,s,D5
	SRCFILE "Songs\SHarrierC64.bas",149
	DECLE 16147,39
	;[150] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",150
	DECLE 16191,63
	;[151] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",151
	DECLE 16191,63
	;[152] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",152
	DECLE 16191,63
	;[153] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",153
	DECLE 6975,34
	;[154] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",154
	DECLE 16191,63
	;[155] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",155
	DECLE 16191,63
	;[156] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",156
	DECLE 16191,63
	;[157] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",157
	DECLE 6463,32
	;[158] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",158
	DECLE 16191,63
	;[159] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",159
	DECLE 16191,63
	;[160] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",160
	DECLE 16191,63
	;[161] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",161
	DECLE 6975,34
	;[162] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",162
	DECLE 16191,63
	;[163] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",163
	DECLE 16191,63
	;[164] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",164
	DECLE 16191,63
	;[165] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",165
	DECLE 16150,31
	;[166] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",166
	DECLE 16191,63
	;[167] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",167
	DECLE 16191,63
	;[168] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",168
	DECLE 16191,63
	;[169] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",169
	DECLE 6975,34
	;[170] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",170
	DECLE 16191,63
	;[171] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",171
	DECLE 16191,63
	;[172] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",172
	DECLE 16191,63
	;[173] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",173
	DECLE 6463,32
	;[174] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",174
	DECLE 16191,63
	;[175] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",175
	DECLE 16191,63
	;[176] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",176
	DECLE 16191,63
	;[177] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",177
	DECLE 6975,34
	;[178] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",178
	DECLE 16191,63
	;[179] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",179
	DECLE 16191,63
	;[180] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",180
	DECLE 16191,63
	;[181] MUSIC F3#,s,D5
	SRCFILE "Songs\SHarrierC64.bas",181
	DECLE 16147,39
	;[182] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",182
	DECLE 16191,63
	;[183] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",183
	DECLE 16191,63
	;[184] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",184
	DECLE 16191,63
	;[185] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",185
	DECLE 6975,34
	;[186] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",186
	DECLE 16191,63
	;[187] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",187
	DECLE 16191,63
	;[188] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",188
	DECLE 16191,63
	;[189] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",189
	DECLE 6463,32
	;[190] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",190
	DECLE 16191,63
	;[191] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",191
	DECLE 16191,63
	;[192] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",192
	DECLE 16191,63
	;[193] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",193
	DECLE 6975,34
	;[194] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",194
	DECLE 16191,63
	;[195] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",195
	DECLE 16191,63
	;[196] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",196
	DECLE 16191,63
	;[197] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",197
	DECLE 16150,31
	;[198] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",198
	DECLE 16191,63
	;[199] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",199
	DECLE 16191,63
	;[200] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",200
	DECLE 16191,63
	;[201] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",201
	DECLE 6975,34
	;[202] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",202
	DECLE 16191,63
	;[203] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",203
	DECLE 16191,63
	;[204] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",204
	DECLE 16191,63
	;[205] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",205
	DECLE 6463,32
	;[206] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",206
	DECLE 16191,63
	;[207] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",207
	DECLE 16191,63
	;[208] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",208
	DECLE 16191,63
	;[209] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",209
	DECLE 6975,34
	;[210] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",210
	DECLE 16191,63
	;[211] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",211
	DECLE 16191,63
	;[212] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",212
	DECLE 16191,63
	;[213] MUSIC G3,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",213
	DECLE 16148,35
	;[214] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",214
	DECLE 16191,63
	;[215] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",215
	DECLE 16191,63
	;[216] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",216
	DECLE 16191,63
	;[217] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",217
	DECLE 6975,32
	;[218] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",218
	DECLE 16191,63
	;[219] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",219
	DECLE 16191,63
	;[220] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",220
	DECLE 16191,63
	;[221] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",221
	DECLE 6463,31
	;[222] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",222
	DECLE 16191,63
	;[223] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",223
	DECLE 16191,63
	;[224] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",224
	DECLE 16191,63
	;[225] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",225
	DECLE 6975,32
	;[226] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",226
	DECLE 16191,63
	;[227] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",227
	DECLE 16191,63
	;[228] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",228
	DECLE 16191,63
	;[229] MUSIC A3#,s,D4
	SRCFILE "Songs\SHarrierC64.bas",229
	DECLE 16151,27
	;[230] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",230
	DECLE 16191,63
	;[231] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",231
	DECLE 16191,63
	;[232] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",232
	DECLE 16191,63
	;[233] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",233
	DECLE 6975,32
	;[234] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",234
	DECLE 16191,63
	;[235] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",235
	DECLE 16191,63
	;[236] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",236
	DECLE 16191,63
	;[237] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",237
	DECLE 6463,31
	;[238] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",238
	DECLE 16191,63
	;[239] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",239
	DECLE 16191,63
	;[240] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",240
	DECLE 16191,63
	;[241] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",241
	DECLE 6975,32
	;[242] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",242
	DECLE 16191,63
	;[243] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",243
	DECLE 16191,63
	;[244] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",244
	DECLE 16191,63
	;[245] MUSIC G3,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",245
	DECLE 16148,35
	;[246] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",246
	DECLE 16191,63
	;[247] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",247
	DECLE 16191,63
	;[248] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",248
	DECLE 16191,63
	;[249] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",249
	DECLE 6975,32
	;[250] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",250
	DECLE 16191,63
	;[251] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",251
	DECLE 16191,63
	;[252] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",252
	DECLE 16191,63
	;[253] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",253
	DECLE 6463,31
	;[254] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",254
	DECLE 16191,63
	;[255] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",255
	DECLE 16191,63
	;[256] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",256
	DECLE 16191,63
	;[257] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",257
	DECLE 6975,32
	;[258] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",258
	DECLE 16191,63
	;[259] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",259
	DECLE 16191,63
	;[260] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",260
	DECLE 16191,63
	;[261] MUSIC A3#,s,D4
	SRCFILE "Songs\SHarrierC64.bas",261
	DECLE 16151,27
	;[262] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",262
	DECLE 16191,63
	;[263] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",263
	DECLE 16191,63
	;[264] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",264
	DECLE 16191,63
	;[265] 
	SRCFILE "Songs\SHarrierC64.bas",265
	;[266] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",266
	DECLE 6975,32
	;[267] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",267
	DECLE 16191,63
	;[268] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",268
	DECLE 16191,63
	;[269] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",269
	DECLE 16191,63
	;[270] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",270
	DECLE 6463,31
	;[271] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",271
	DECLE 16191,63
	;[272] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",272
	DECLE 16191,63
	;[273] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",273
	DECLE 16191,63
	;[274] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",274
	DECLE 6975,32
	;[275] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",275
	DECLE 16191,63
	;[276] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",276
	DECLE 16191,63
	;[277] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",277
	DECLE 16191,63
	;[278] MUSIC D3#,s,C5
	SRCFILE "Songs\SHarrierC64.bas",278
	DECLE 16144,37
	;[279] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",279
	DECLE 16191,63
	;[280] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",280
	DECLE 16191,63
	;[281] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",281
	DECLE 16191,63
	;[282] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",282
	DECLE 6463,32
	;[283] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",283
	DECLE 16191,63
	;[284] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",284
	DECLE 16191,63
	;[285] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",285
	DECLE 16191,63
	;[286] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",286
	DECLE 16150,31
	;[287] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",287
	DECLE 16191,63
	;[288] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",288
	DECLE 16191,63
	;[289] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",289
	DECLE 16191,63
	;[290] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",290
	DECLE 6463,32
	;[291] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",291
	DECLE 16191,63
	;[292] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",292
	DECLE 16191,63
	;[293] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",293
	DECLE 16191,63
	;[294] MUSIC s,G3,D4#
	SRCFILE "Songs\SHarrierC64.bas",294
	DECLE 5183,28
	;[295] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",295
	DECLE 16191,63
	;[296] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",296
	DECLE 16191,63
	;[297] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",297
	DECLE 16191,63
	;[298] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",298
	DECLE 6463,32
	;[299] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",299
	DECLE 16191,63
	;[300] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",300
	DECLE 16191,63
	;[301] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",301
	DECLE 16191,63
	;[302] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",302
	DECLE 16150,31
	;[303] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",303
	DECLE 16191,63
	;[304] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",304
	DECLE 16191,63
	;[305] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",305
	DECLE 16191,63
	;[306] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",306
	DECLE 6463,32
	;[307] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",307
	DECLE 16191,63
	;[308] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",308
	DECLE 16191,63
	;[309] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",309
	DECLE 16191,63
	;[310] MUSIC D3#,s,C5
	SRCFILE "Songs\SHarrierC64.bas",310
	DECLE 16144,37
	;[311] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",311
	DECLE 16191,63
	;[312] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",312
	DECLE 16191,63
	;[313] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",313
	DECLE 16191,63
	;[314] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",314
	DECLE 6463,32
	;[315] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",315
	DECLE 16191,63
	;[316] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",316
	DECLE 16191,63
	;[317] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",317
	DECLE 16191,63
	;[318] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",318
	DECLE 16150,31
	;[319] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",319
	DECLE 16191,63
	;[320] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",320
	DECLE 16191,63
	;[321] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",321
	DECLE 16191,63
	;[322] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",322
	DECLE 6463,32
	;[323] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",323
	DECLE 16191,63
	;[324] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",324
	DECLE 16191,63
	;[325] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",325
	DECLE 16191,63
	;[326] MUSIC G3,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",326
	DECLE 16148,28
	;[327] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",327
	DECLE 16191,63
	;[328] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",328
	DECLE 16191,63
	;[329] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",329
	DECLE 16191,63
	;[330] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",330
	DECLE 6463,32
	;[331] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",331
	DECLE 16191,63
	;[332] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",332
	DECLE 16191,63
	;[333] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",333
	DECLE 16191,63
	;[334] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",334
	DECLE 16150,31
	;[335] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",335
	DECLE 16191,63
	;[336] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",336
	DECLE 16191,63
	;[337] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",337
	DECLE 16191,63
	;[338] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",338
	DECLE 6463,32
	;[339] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",339
	DECLE 16191,63
	;[340] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",340
	DECLE 16191,63
	;[341] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",341
	DECLE 16191,63
	;[342] MUSIC D3,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",342
	DECLE 16143,35
	;[343] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",343
	DECLE 16191,63
	;[344] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",344
	DECLE 16191,63
	;[345] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",345
	DECLE 16191,63
	;[346] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",346
	DECLE 5951,32
	;[347] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",347
	DECLE 16191,63
	;[348] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",348
	DECLE 16191,63
	;[349] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",349
	DECLE 16191,63
	;[350] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",350
	DECLE 16150,31
	;[351] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",351
	DECLE 16191,63
	;[352] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",352
	DECLE 16191,63
	;[353] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",353
	DECLE 16191,63
	;[354] MUSIC A3#,G4,s
	SRCFILE "Songs\SHarrierC64.bas",354
	DECLE 8215,63
	;[355] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",355
	DECLE 16191,63
	;[356] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",356
	DECLE 16191,63
	;[357] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",357
	DECLE 16191,63
	;[358] MUSIC s,G3,D4
	SRCFILE "Songs\SHarrierC64.bas",358
	DECLE 5183,27
	;[359] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",359
	DECLE 16191,63
	;[360] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",360
	DECLE 16191,63
	;[361] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",361
	DECLE 16191,63
	;[362] MUSIC A3#,G4,s
	SRCFILE "Songs\SHarrierC64.bas",362
	DECLE 8215,63
	;[363] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",363
	DECLE 16191,63
	;[364] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",364
	DECLE 16191,63
	;[365] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",365
	DECLE 16191,63
	;[366] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",366
	DECLE 5695,31
	;[367] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",367
	DECLE 16191,63
	;[368] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",368
	DECLE 16191,63
	;[369] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",369
	DECLE 16191,63
	;[370] MUSIC G4,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",370
	DECLE 5920,63
	;[371] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",371
	DECLE 16191,63
	;[372] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",372
	DECLE 16191,63
	;[373] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",373
	DECLE 16191,63
	;[374] MUSIC s,D3,A4#
	SRCFILE "Songs\SHarrierC64.bas",374
	DECLE 3903,35
	;[375] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",375
	DECLE 16191,63
	;[376] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",376
	DECLE 16191,63
	;[377] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",377
	DECLE 16191,63
	;[378] MUSIC A3#,s,G4
	SRCFILE "Songs\SHarrierC64.bas",378
	DECLE 16151,32
	;[379] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",379
	DECLE 16191,63
	;[380] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",380
	DECLE 16191,63
	;[381] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",381
	DECLE 16191,63
	;[382] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",382
	DECLE 5695,31
	;[383] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",383
	DECLE 16191,63
	;[384] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",384
	DECLE 16191,63
	;[385] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",385
	DECLE 16191,63
	;[386] MUSIC G4,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",386
	DECLE 5920,63
	;[387] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",387
	DECLE 16191,63
	;[388] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",388
	DECLE 16191,63
	;[389] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",389
	DECLE 16191,63
	;[390] MUSIC s,G3,D4
	SRCFILE "Songs\SHarrierC64.bas",390
	DECLE 5183,27
	;[391] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",391
	DECLE 16191,63
	;[392] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",392
	DECLE 16191,63
	;[393] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",393
	DECLE 16191,63
	;[394] 
	SRCFILE "Songs\SHarrierC64.bas",394
	;[395] MUSIC A3#,s,G4
	SRCFILE "Songs\SHarrierC64.bas",395
	DECLE 16151,32
	;[396] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",396
	DECLE 16191,63
	;[397] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",397
	DECLE 16191,63
	;[398] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",398
	DECLE 16191,63
	;[399] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",399
	DECLE 5695,31
	;[400] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",400
	DECLE 16191,63
	;[401] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",401
	DECLE 16191,63
	;[402] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",402
	DECLE 16191,63
	;[403] MUSIC G4,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",403
	DECLE 5920,63
	;[404] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",404
	DECLE 16191,63
	;[405] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",405
	DECLE 16191,63
	;[406] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",406
	DECLE 16191,63
	;[407] MUSIC s,D3,A4
	SRCFILE "Songs\SHarrierC64.bas",407
	DECLE 3903,34
	;[408] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",408
	DECLE 16191,63
	;[409] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",409
	DECLE 16191,63
	;[410] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",410
	DECLE 16191,63
	;[411] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",411
	DECLE 16150,31
	;[412] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",412
	DECLE 16191,63
	;[413] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",413
	DECLE 16191,63
	;[414] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",414
	DECLE 16191,63
	;[415] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",415
	DECLE 5183,29
	;[416] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",416
	DECLE 16191,63
	;[417] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",417
	DECLE 16191,63
	;[418] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",418
	DECLE 16191,63
	;[419] MUSIC F4#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",419
	DECLE 5663,63
	;[420] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",420
	DECLE 16191,63
	;[421] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",421
	DECLE 16191,63
	;[422] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",422
	DECLE 16191,63
	;[423] MUSIC s,F3#,D4
	SRCFILE "Songs\SHarrierC64.bas",423
	DECLE 4927,27
	;[424] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",424
	DECLE 16191,63
	;[425] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",425
	DECLE 16191,63
	;[426] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",426
	DECLE 16191,63
	;[427] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",427
	DECLE 16150,31
	;[428] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",428
	DECLE 16191,63
	;[429] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",429
	DECLE 16191,63
	;[430] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",430
	DECLE 16191,63
	;[431] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",431
	DECLE 5183,29
	;[432] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",432
	DECLE 16191,63
	;[433] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",433
	DECLE 16191,63
	;[434] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",434
	DECLE 16191,63
	;[435] MUSIC F4#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",435
	DECLE 5663,63
	;[436] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",436
	DECLE 16191,63
	;[437] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",437
	DECLE 16191,63
	;[438] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",438
	DECLE 16191,63
	;[439] MUSIC s,D3,A4
	SRCFILE "Songs\SHarrierC64.bas",439
	DECLE 3903,34
	;[440] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",440
	DECLE 16191,63
	;[441] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",441
	DECLE 16191,63
	;[442] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",442
	DECLE 16191,63
	;[443] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",443
	DECLE 16150,31
	;[444] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",444
	DECLE 16191,63
	;[445] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",445
	DECLE 16191,63
	;[446] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",446
	DECLE 16191,63
	;[447] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",447
	DECLE 5183,29
	;[448] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",448
	DECLE 16191,63
	;[449] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",449
	DECLE 16191,63
	;[450] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",450
	DECLE 16191,63
	;[451] MUSIC F4#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",451
	DECLE 5663,63
	;[452] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",452
	DECLE 16191,63
	;[453] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",453
	DECLE 16191,63
	;[454] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",454
	DECLE 16191,63
	;[455] MUSIC s,F3#,D4
	SRCFILE "Songs\SHarrierC64.bas",455
	DECLE 4927,27
	;[456] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",456
	DECLE 16191,63
	;[457] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",457
	DECLE 16191,63
	;[458] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",458
	DECLE 16191,63
	;[459] MUSIC A3,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",459
	DECLE 16150,31
	;[460] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",460
	DECLE 16191,63
	;[461] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",461
	DECLE 16191,63
	;[462] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",462
	DECLE 16191,63
	;[463] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",463
	DECLE 5183,29
	;[464] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",464
	DECLE 16191,63
	;[465] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",465
	DECLE 16191,63
	;[466] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",466
	DECLE 16191,63
	;[467] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",467
	DECLE 5695,31
	;[468] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",468
	DECLE 16191,63
	;[469] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",469
	DECLE 16191,63
	;[470] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",470
	DECLE 16191,63
	;[471] MUSIC G3,s,G4
	SRCFILE "Songs\SHarrierC64.bas",471
	DECLE 16148,32
	;[472] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",472
	DECLE 16191,63
	;[473] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",473
	DECLE 16191,63
	;[474] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",474
	DECLE 16191,63
	;[475] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",475
	DECLE 6975,63
	;[476] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",476
	DECLE 16191,63
	;[477] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",477
	DECLE 16191,63
	;[478] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",478
	DECLE 16191,63
	;[479] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",479
	DECLE 6463,63
	;[480] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",480
	DECLE 16191,63
	;[481] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",481
	DECLE 16191,63
	;[482] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",482
	DECLE 16191,63
	;[483] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",483
	DECLE 6975,63
	;[484] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",484
	DECLE 16191,63
	;[485] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",485
	DECLE 16191,63
	;[486] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",486
	DECLE 16191,63
	;[487] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",487
	DECLE 5951,63
	;[488] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",488
	DECLE 16191,63
	;[489] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",489
	DECLE 16191,63
	;[490] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",490
	DECLE 16191,63
	;[491] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",491
	DECLE 6975,63
	;[492] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",492
	DECLE 16191,63
	;[493] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",493
	DECLE 16191,63
	;[494] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",494
	DECLE 16191,63
	;[495] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",495
	DECLE 5695,63
	;[496] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",496
	DECLE 16191,63
	;[497] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",497
	DECLE 16191,63
	;[498] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",498
	DECLE 16191,63
	;[499] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",499
	DECLE 6975,63
	;[500] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",500
	DECLE 16191,63
	;[501] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",501
	DECLE 16191,63
	;[502] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",502
	DECLE 16191,63
	;[503] MUSIC s,D3,A4
	SRCFILE "Songs\SHarrierC64.bas",503
	DECLE 3903,34
	;[504] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",504
	DECLE 16143,63
	;[505] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",505
	DECLE 16191,63
	;[506] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",506
	DECLE 16191,63
	;[507] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",507
	DECLE 6975,63
	;[508] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",508
	DECLE 16191,63
	;[509] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",509
	DECLE 16191,63
	;[510] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",510
	DECLE 16191,63
	;[511] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",511
	DECLE 6463,63
	;[512] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",512
	DECLE 16191,63
	;[513] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",513
	DECLE 16191,63
	;[514] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",514
	DECLE 16191,63
	;[515] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",515
	DECLE 6975,63
	;[516] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",516
	DECLE 16191,63
	;[517] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",517
	DECLE 16191,63
	;[518] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",518
	DECLE 16191,63
	;[519] MUSIC s,A3,F5#
	SRCFILE "Songs\SHarrierC64.bas",519
	DECLE 5695,43
	;[520] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",520
	DECLE 16143,63
	;[521] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",521
	DECLE 16191,63
	;[522] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",522
	DECLE 16191,63
	;[523] 
	SRCFILE "Songs\SHarrierC64.bas",523
	;[524] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",524
	DECLE 6975,63
	;[525] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",525
	DECLE 16191,63
	;[526] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",526
	DECLE 16191,63
	;[527] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",527
	DECLE 16191,63
	;[528] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",528
	DECLE 6463,63
	;[529] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",529
	DECLE 16191,63
	;[530] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",530
	DECLE 16191,63
	;[531] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",531
	DECLE 16191,63
	;[532] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",532
	DECLE 6975,63
	;[533] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",533
	DECLE 16191,63
	;[534] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",534
	DECLE 16191,63
	;[535] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",535
	DECLE 16191,63
	;[536] MUSIC s,G3,D5
	SRCFILE "Songs\SHarrierC64.bas",536
	DECLE 5183,39
	;[537] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",537
	DECLE 16136,63
	;[538] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",538
	DECLE 16191,63
	;[539] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",539
	DECLE 16191,63
	;[540] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",540
	DECLE 6975,35
	;[541] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",541
	DECLE 16191,63
	;[542] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",542
	DECLE 16191,63
	;[543] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",543
	DECLE 16191,63
	;[544] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",544
	DECLE 6463,34
	;[545] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",545
	DECLE 16148,63
	;[546] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",546
	DECLE 16191,63
	;[547] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",547
	DECLE 16191,63
	;[548] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",548
	DECLE 6975,35
	;[549] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",549
	DECLE 16191,63
	;[550] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",550
	DECLE 16191,63
	;[551] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",551
	DECLE 16191,63
	;[552] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",552
	DECLE 5951,32
	;[553] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",553
	DECLE 16136,63
	;[554] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",554
	DECLE 16191,63
	;[555] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",555
	DECLE 16191,63
	;[556] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",556
	DECLE 6975,35
	;[557] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",557
	DECLE 16191,63
	;[558] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",558
	DECLE 16191,63
	;[559] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",559
	DECLE 16191,63
	;[560] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",560
	DECLE 6463,34
	;[561] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",561
	DECLE 16148,63
	;[562] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",562
	DECLE 16191,63
	;[563] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",563
	DECLE 16191,63
	;[564] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",564
	DECLE 6975,35
	;[565] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",565
	DECLE 16191,63
	;[566] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",566
	DECLE 16191,63
	;[567] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",567
	DECLE 16191,63
	;[568] MUSIC s,G3,D5
	SRCFILE "Songs\SHarrierC64.bas",568
	DECLE 5183,39
	;[569] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",569
	DECLE 16136,63
	;[570] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",570
	DECLE 16191,63
	;[571] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",571
	DECLE 16191,63
	;[572] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",572
	DECLE 6975,35
	;[573] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",573
	DECLE 16191,63
	;[574] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",574
	DECLE 16191,63
	;[575] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",575
	DECLE 16191,63
	;[576] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",576
	DECLE 6463,34
	;[577] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",577
	DECLE 16148,63
	;[578] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",578
	DECLE 16191,63
	;[579] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",579
	DECLE 16191,63
	;[580] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",580
	DECLE 6975,35
	;[581] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",581
	DECLE 16191,63
	;[582] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",582
	DECLE 16191,63
	;[583] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",583
	DECLE 16191,63
	;[584] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",584
	DECLE 5951,32
	;[585] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",585
	DECLE 16136,63
	;[586] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",586
	DECLE 16191,63
	;[587] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",587
	DECLE 16191,63
	;[588] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",588
	DECLE 6975,35
	;[589] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",589
	DECLE 16191,63
	;[590] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",590
	DECLE 16191,63
	;[591] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",591
	DECLE 16191,63
	;[592] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",592
	DECLE 6463,34
	;[593] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",593
	DECLE 16148,63
	;[594] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",594
	DECLE 16191,63
	;[595] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",595
	DECLE 16191,63
	;[596] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",596
	DECLE 6975,35
	;[597] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",597
	DECLE 16191,63
	;[598] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",598
	DECLE 16191,63
	;[599] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",599
	DECLE 16191,63
	;[600] MUSIC s,G3,D5#
	SRCFILE "Songs\SHarrierC64.bas",600
	DECLE 5183,40
	;[601] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",601
	DECLE 16136,63
	;[602] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",602
	DECLE 16191,63
	;[603] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",603
	DECLE 16191,63
	;[604] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",604
	DECLE 7231,37
	;[605] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",605
	DECLE 16191,63
	;[606] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",606
	DECLE 16191,63
	;[607] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",607
	DECLE 16191,63
	;[608] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",608
	DECLE 6975,36
	;[609] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",609
	DECLE 16148,63
	;[610] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",610
	DECLE 16191,63
	;[611] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",611
	DECLE 16191,63
	;[612] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",612
	DECLE 7231,37
	;[613] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",613
	DECLE 16191,63
	;[614] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",614
	DECLE 16191,63
	;[615] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",615
	DECLE 16191,63
	;[616] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",616
	DECLE 6463,32
	;[617] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",617
	DECLE 16136,63
	;[618] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",618
	DECLE 16191,63
	;[619] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",619
	DECLE 16191,63
	;[620] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",620
	DECLE 7231,37
	;[621] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",621
	DECLE 16191,63
	;[622] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",622
	DECLE 16191,63
	;[623] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",623
	DECLE 16191,63
	;[624] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",624
	DECLE 6975,36
	;[625] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",625
	DECLE 16148,63
	;[626] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",626
	DECLE 16191,63
	;[627] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",627
	DECLE 16191,63
	;[628] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",628
	DECLE 7231,37
	;[629] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",629
	DECLE 16191,63
	;[630] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",630
	DECLE 16191,63
	;[631] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",631
	DECLE 16191,63
	;[632] MUSIC s,G3,D5#
	SRCFILE "Songs\SHarrierC64.bas",632
	DECLE 5183,40
	;[633] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",633
	DECLE 16136,63
	;[634] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",634
	DECLE 16191,63
	;[635] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",635
	DECLE 16191,63
	;[636] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",636
	DECLE 7231,37
	;[637] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",637
	DECLE 16191,63
	;[638] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",638
	DECLE 16191,63
	;[639] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",639
	DECLE 16191,63
	;[640] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",640
	DECLE 6975,36
	;[641] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",641
	DECLE 16148,63
	;[642] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",642
	DECLE 16191,63
	;[643] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",643
	DECLE 16191,63
	;[644] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",644
	DECLE 7231,37
	;[645] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",645
	DECLE 16191,63
	;[646] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",646
	DECLE 16191,63
	;[647] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",647
	DECLE 16191,63
	;[648] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",648
	DECLE 6463,32
	;[649] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",649
	DECLE 16136,63
	;[650] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",650
	DECLE 16191,63
	;[651] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",651
	DECLE 16191,63
	;[652] 
	SRCFILE "Songs\SHarrierC64.bas",652
	;[653] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",653
	DECLE 7231,37
	;[654] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",654
	DECLE 16191,63
	;[655] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",655
	DECLE 16191,63
	;[656] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",656
	DECLE 16191,63
	;[657] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",657
	DECLE 6975,36
	;[658] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",658
	DECLE 16148,63
	;[659] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",659
	DECLE 16191,63
	;[660] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",660
	DECLE 16191,63
	;[661] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",661
	DECLE 7231,37
	;[662] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",662
	DECLE 16191,63
	;[663] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",663
	DECLE 16191,63
	;[664] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",664
	DECLE 16191,63
	;[665] MUSIC s,F3#,D5
	SRCFILE "Songs\SHarrierC64.bas",665
	DECLE 4927,39
	;[666] MUSIC F2#,s,s
	SRCFILE "Songs\SHarrierC64.bas",666
	DECLE 16135,63
	;[667] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",667
	DECLE 16191,63
	;[668] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",668
	DECLE 16191,63
	;[669] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",669
	DECLE 6975,34
	;[670] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",670
	DECLE 16191,63
	;[671] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",671
	DECLE 16191,63
	;[672] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",672
	DECLE 16191,63
	;[673] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",673
	DECLE 6463,32
	;[674] MUSIC F3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",674
	DECLE 16147,63
	;[675] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",675
	DECLE 16191,63
	;[676] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",676
	DECLE 16191,63
	;[677] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",677
	DECLE 6975,34
	;[678] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",678
	DECLE 16191,63
	;[679] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",679
	DECLE 16191,63
	;[680] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",680
	DECLE 16191,63
	;[681] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",681
	DECLE 5695,31
	;[682] MUSIC F2#,s,s
	SRCFILE "Songs\SHarrierC64.bas",682
	DECLE 16135,63
	;[683] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",683
	DECLE 16191,63
	;[684] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",684
	DECLE 16191,63
	;[685] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",685
	DECLE 6975,34
	;[686] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",686
	DECLE 16191,63
	;[687] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",687
	DECLE 16191,63
	;[688] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",688
	DECLE 16191,63
	;[689] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",689
	DECLE 6463,32
	;[690] MUSIC F3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",690
	DECLE 16147,63
	;[691] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",691
	DECLE 16191,63
	;[692] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",692
	DECLE 16191,63
	;[693] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",693
	DECLE 6975,34
	;[694] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",694
	DECLE 16191,63
	;[695] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",695
	DECLE 16191,63
	;[696] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",696
	DECLE 16191,63
	;[697] MUSIC s,F3#,D5
	SRCFILE "Songs\SHarrierC64.bas",697
	DECLE 4927,39
	;[698] MUSIC F2#,s,s
	SRCFILE "Songs\SHarrierC64.bas",698
	DECLE 16135,63
	;[699] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",699
	DECLE 16191,63
	;[700] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",700
	DECLE 16191,63
	;[701] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",701
	DECLE 6975,34
	;[702] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",702
	DECLE 16191,63
	;[703] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",703
	DECLE 16191,63
	;[704] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",704
	DECLE 16191,63
	;[705] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",705
	DECLE 6463,32
	;[706] MUSIC F3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",706
	DECLE 16147,63
	;[707] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",707
	DECLE 16191,63
	;[708] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",708
	DECLE 16191,63
	;[709] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",709
	DECLE 6975,34
	;[710] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",710
	DECLE 16191,63
	;[711] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",711
	DECLE 16191,63
	;[712] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",712
	DECLE 16191,63
	;[713] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",713
	DECLE 5695,31
	;[714] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",714
	DECLE 16143,63
	;[715] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",715
	DECLE 16191,63
	;[716] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",716
	DECLE 16191,63
	;[717] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",717
	DECLE 6975,34
	;[718] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",718
	DECLE 16191,63
	;[719] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",719
	DECLE 16191,63
	;[720] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",720
	DECLE 16191,63
	;[721] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",721
	DECLE 6463,32
	;[722] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",722
	DECLE 16143,63
	;[723] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",723
	DECLE 16191,63
	;[724] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",724
	DECLE 16191,63
	;[725] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",725
	DECLE 6975,34
	;[726] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",726
	DECLE 16191,63
	;[727] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",727
	DECLE 16191,63
	;[728] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",728
	DECLE 16191,63
	;[729] MUSIC s,G3,A4#
	SRCFILE "Songs\SHarrierC64.bas",729
	DECLE 5183,35
	;[730] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",730
	DECLE 16136,63
	;[731] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",731
	DECLE 16191,63
	;[732] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",732
	DECLE 16191,63
	;[733] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",733
	DECLE 6975,32
	;[734] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",734
	DECLE 16191,63
	;[735] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",735
	DECLE 16191,63
	;[736] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",736
	DECLE 16191,63
	;[737] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",737
	DECLE 6463,31
	;[738] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",738
	DECLE 16148,63
	;[739] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",739
	DECLE 16191,63
	;[740] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",740
	DECLE 16191,63
	;[741] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",741
	DECLE 16191,32
	;[742] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",742
	DECLE 6975,63
	;[743] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",743
	DECLE 16191,63
	;[744] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",744
	DECLE 16191,63
	;[745] MUSIC s,A3#,D4
	SRCFILE "Songs\SHarrierC64.bas",745
	DECLE 5951,27
	;[746] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",746
	DECLE 16136,63
	;[747] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",747
	DECLE 16191,63
	;[748] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",748
	DECLE 16191,63
	;[749] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",749
	DECLE 6975,32
	;[750] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",750
	DECLE 16191,63
	;[751] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",751
	DECLE 16191,63
	;[752] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",752
	DECLE 16191,63
	;[753] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",753
	DECLE 6463,31
	;[754] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",754
	DECLE 16148,63
	;[755] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",755
	DECLE 16191,63
	;[756] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",756
	DECLE 16191,63
	;[757] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",757
	DECLE 6975,32
	;[758] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",758
	DECLE 16191,63
	;[759] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",759
	DECLE 16191,63
	;[760] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",760
	DECLE 16191,63
	;[761] MUSIC s,G3,A4#
	SRCFILE "Songs\SHarrierC64.bas",761
	DECLE 5183,35
	;[762] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",762
	DECLE 16136,63
	;[763] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",763
	DECLE 16191,63
	;[764] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",764
	DECLE 16191,63
	;[765] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",765
	DECLE 6975,32
	;[766] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",766
	DECLE 16191,63
	;[767] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",767
	DECLE 16191,63
	;[768] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",768
	DECLE 16191,63
	;[769] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",769
	DECLE 6463,31
	;[770] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",770
	DECLE 16148,63
	;[771] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",771
	DECLE 16191,63
	;[772] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",772
	DECLE 16191,63
	;[773] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",773
	DECLE 6975,32
	;[774] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",774
	DECLE 16191,63
	;[775] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",775
	DECLE 16191,63
	;[776] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",776
	DECLE 16191,63
	;[777] MUSIC s,A3#,D4
	SRCFILE "Songs\SHarrierC64.bas",777
	DECLE 5951,27
	;[778] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",778
	DECLE 16136,63
	;[779] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",779
	DECLE 16191,63
	;[780] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",780
	DECLE 16191,63
	;[781] 
	SRCFILE "Songs\SHarrierC64.bas",781
	;[782] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",782
	DECLE 6975,32
	;[783] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",783
	DECLE 16191,63
	;[784] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",784
	DECLE 16191,63
	;[785] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",785
	DECLE 16191,63
	;[786] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",786
	DECLE 6463,31
	;[787] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",787
	DECLE 16148,63
	;[788] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",788
	DECLE 16191,63
	;[789] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",789
	DECLE 16191,63
	;[790] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",790
	DECLE 6975,32
	;[791] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",791
	DECLE 16191,63
	;[792] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",792
	DECLE 16191,63
	;[793] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",793
	DECLE 16191,63
	;[794] MUSIC s,D3#,C5
	SRCFILE "Songs\SHarrierC64.bas",794
	DECLE 4159,37
	;[795] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",795
	DECLE 16144,63
	;[796] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",796
	DECLE 16191,63
	;[797] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",797
	DECLE 16191,63
	;[798] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",798
	DECLE 6463,32
	;[799] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",799
	DECLE 16191,63
	;[800] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",800
	DECLE 16191,63
	;[801] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",801
	DECLE 16191,63
	;[802] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",802
	DECLE 5695,31
	;[803] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",803
	DECLE 16144,63
	;[804] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",804
	DECLE 16191,63
	;[805] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",805
	DECLE 16191,63
	;[806] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",806
	DECLE 6463,32
	;[807] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",807
	DECLE 16191,63
	;[808] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",808
	DECLE 16191,63
	;[809] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",809
	DECLE 16191,63
	;[810] MUSIC s,G3,D4#
	SRCFILE "Songs\SHarrierC64.bas",810
	DECLE 5183,28
	;[811] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",811
	DECLE 16144,63
	;[812] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",812
	DECLE 16191,63
	;[813] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",813
	DECLE 16191,63
	;[814] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",814
	DECLE 6463,32
	;[815] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",815
	DECLE 16191,63
	;[816] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",816
	DECLE 16191,63
	;[817] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",817
	DECLE 16191,63
	;[818] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",818
	DECLE 5695,31
	;[819] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",819
	DECLE 16144,63
	;[820] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",820
	DECLE 16191,63
	;[821] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",821
	DECLE 16191,63
	;[822] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",822
	DECLE 6463,32
	;[823] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",823
	DECLE 16191,63
	;[824] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",824
	DECLE 16191,63
	;[825] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",825
	DECLE 16191,63
	;[826] MUSIC s,D3#,C5
	SRCFILE "Songs\SHarrierC64.bas",826
	DECLE 4159,37
	;[827] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",827
	DECLE 16144,63
	;[828] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",828
	DECLE 16191,63
	;[829] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",829
	DECLE 16191,63
	;[830] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",830
	DECLE 6463,32
	;[831] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",831
	DECLE 16191,63
	;[832] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",832
	DECLE 16191,63
	;[833] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",833
	DECLE 16191,63
	;[834] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",834
	DECLE 5695,31
	;[835] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",835
	DECLE 16144,63
	;[836] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",836
	DECLE 16191,63
	;[837] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",837
	DECLE 16191,63
	;[838] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",838
	DECLE 6463,32
	;[839] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",839
	DECLE 16191,63
	;[840] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",840
	DECLE 16191,63
	;[841] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",841
	DECLE 16191,63
	;[842] MUSIC s,G3,D4#
	SRCFILE "Songs\SHarrierC64.bas",842
	DECLE 5183,28
	;[843] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",843
	DECLE 16144,63
	;[844] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",844
	DECLE 16191,63
	;[845] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",845
	DECLE 16191,63
	;[846] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",846
	DECLE 6463,32
	;[847] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",847
	DECLE 16191,63
	;[848] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",848
	DECLE 16191,63
	;[849] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",849
	DECLE 16191,63
	;[850] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",850
	DECLE 5695,31
	;[851] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",851
	DECLE 16144,63
	;[852] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",852
	DECLE 16191,63
	;[853] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",853
	DECLE 16191,63
	;[854] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",854
	DECLE 6463,32
	;[855] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",855
	DECLE 16191,63
	;[856] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",856
	DECLE 16191,63
	;[857] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",857
	DECLE 16191,63
	;[858] MUSIC s,D3,A4#
	SRCFILE "Songs\SHarrierC64.bas",858
	DECLE 3903,35
	;[859] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",859
	DECLE 16143,63
	;[860] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",860
	DECLE 16191,63
	;[861] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",861
	DECLE 16191,63
	;[862] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",862
	DECLE 5951,32
	;[863] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",863
	DECLE 16191,63
	;[864] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",864
	DECLE 16191,63
	;[865] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",865
	DECLE 16191,63
	;[866] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",866
	DECLE 5695,31
	;[867] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",867
	DECLE 16143,63
	;[868] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",868
	DECLE 16191,63
	;[869] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",869
	DECLE 16191,63
	;[870] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",870
	DECLE 5951,32
	;[871] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",871
	DECLE 16191,63
	;[872] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",872
	DECLE 16191,63
	;[873] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",873
	DECLE 16191,63
	;[874] MUSIC s,G3,D4
	SRCFILE "Songs\SHarrierC64.bas",874
	DECLE 5183,27
	;[875] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",875
	DECLE 16143,63
	;[876] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",876
	DECLE 16191,63
	;[877] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",877
	DECLE 16191,63
	;[878] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",878
	DECLE 5951,32
	;[879] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",879
	DECLE 16191,63
	;[880] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",880
	DECLE 16191,63
	;[881] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",881
	DECLE 16191,63
	;[882] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",882
	DECLE 5695,31
	;[883] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",883
	DECLE 16143,63
	;[884] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",884
	DECLE 16191,63
	;[885] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",885
	DECLE 16191,63
	;[886] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",886
	DECLE 5951,32
	;[887] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",887
	DECLE 16191,63
	;[888] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",888
	DECLE 16191,63
	;[889] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",889
	DECLE 16191,63
	;[890] MUSIC s,D3,A4#
	SRCFILE "Songs\SHarrierC64.bas",890
	DECLE 3903,35
	;[891] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",891
	DECLE 16143,63
	;[892] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",892
	DECLE 16191,63
	;[893] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",893
	DECLE 16191,63
	;[894] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",894
	DECLE 5951,32
	;[895] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",895
	DECLE 16191,63
	;[896] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",896
	DECLE 16191,63
	;[897] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",897
	DECLE 16191,63
	;[898] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",898
	DECLE 5695,31
	;[899] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",899
	DECLE 16143,63
	;[900] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",900
	DECLE 16191,63
	;[901] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",901
	DECLE 16191,63
	;[902] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",902
	DECLE 5951,32
	;[903] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",903
	DECLE 16191,63
	;[904] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",904
	DECLE 16191,63
	;[905] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",905
	DECLE 16191,63
	;[906] MUSIC s,G3,D4
	SRCFILE "Songs\SHarrierC64.bas",906
	DECLE 5183,27
	;[907] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",907
	DECLE 16143,63
	;[908] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",908
	DECLE 16191,63
	;[909] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",909
	DECLE 16191,63
	;[910] 
	SRCFILE "Songs\SHarrierC64.bas",910
	;[911] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",911
	DECLE 5951,32
	;[912] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",912
	DECLE 16191,63
	;[913] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",913
	DECLE 16191,63
	;[914] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",914
	DECLE 16191,63
	;[915] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",915
	DECLE 5695,31
	;[916] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",916
	DECLE 16143,63
	;[917] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",917
	DECLE 16191,63
	;[918] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",918
	DECLE 16191,63
	;[919] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",919
	DECLE 5951,32
	;[920] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",920
	DECLE 16191,63
	;[921] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",921
	DECLE 16191,63
	;[922] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",922
	DECLE 16191,63
	;[923] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",923
	DECLE 16191,34
	;[924] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",924
	DECLE 3855,63
	;[925] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",925
	DECLE 16191,63
	;[926] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",926
	DECLE 16191,63
	;[927] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",927
	DECLE 5695,31
	;[928] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",928
	DECLE 16191,63
	;[929] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",929
	DECLE 16191,63
	;[930] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",930
	DECLE 16191,63
	;[931] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",931
	DECLE 5183,29
	;[932] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",932
	DECLE 16143,63
	;[933] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",933
	DECLE 16191,63
	;[934] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",934
	DECLE 16191,63
	;[935] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",935
	DECLE 5695,31
	;[936] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",936
	DECLE 16191,63
	;[937] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",937
	DECLE 16191,63
	;[938] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",938
	DECLE 16191,63
	;[939] MUSIC s,F3#,D4
	SRCFILE "Songs\SHarrierC64.bas",939
	DECLE 4927,27
	;[940] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",940
	DECLE 16143,63
	;[941] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",941
	DECLE 16191,63
	;[942] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",942
	DECLE 16191,63
	;[943] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",943
	DECLE 5695,31
	;[944] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",944
	DECLE 16191,63
	;[945] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",945
	DECLE 16191,63
	;[946] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",946
	DECLE 16191,63
	;[947] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",947
	DECLE 5183,29
	;[948] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",948
	DECLE 16143,63
	;[949] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",949
	DECLE 16191,63
	;[950] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",950
	DECLE 16191,63
	;[951] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",951
	DECLE 5695,31
	;[952] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",952
	DECLE 16191,63
	;[953] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",953
	DECLE 16191,63
	;[954] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",954
	DECLE 16191,63
	;[955] MUSIC s,D3,A4
	SRCFILE "Songs\SHarrierC64.bas",955
	DECLE 3903,34
	;[956] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",956
	DECLE 16143,63
	;[957] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",957
	DECLE 16191,63
	;[958] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",958
	DECLE 16191,63
	;[959] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",959
	DECLE 5695,31
	;[960] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",960
	DECLE 16191,63
	;[961] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",961
	DECLE 16191,63
	;[962] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",962
	DECLE 16191,63
	;[963] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",963
	DECLE 5183,29
	;[964] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",964
	DECLE 16143,63
	;[965] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",965
	DECLE 16191,63
	;[966] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",966
	DECLE 16191,63
	;[967] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",967
	DECLE 5695,31
	;[968] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",968
	DECLE 16191,63
	;[969] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",969
	DECLE 16191,63
	;[970] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",970
	DECLE 16191,63
	;[971] MUSIC s,F3#,D4
	SRCFILE "Songs\SHarrierC64.bas",971
	DECLE 4927,27
	;[972] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",972
	DECLE 16143,63
	;[973] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",973
	DECLE 16191,63
	;[974] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",974
	DECLE 16191,63
	;[975] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",975
	DECLE 5695,31
	;[976] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",976
	DECLE 16191,63
	;[977] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",977
	DECLE 16191,63
	;[978] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",978
	DECLE 16191,63
	;[979] MUSIC s,G3,E4
	SRCFILE "Songs\SHarrierC64.bas",979
	DECLE 5183,29
	;[980] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",980
	DECLE 16143,63
	;[981] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",981
	DECLE 16191,63
	;[982] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",982
	DECLE 16191,63
	;[983] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",983
	DECLE 5695,31
	;[984] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",984
	DECLE 16191,63
	;[985] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",985
	DECLE 16191,63
	;[986] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",986
	DECLE 16191,63
	;[987] MUSIC s,G3,G4
	SRCFILE "Songs\SHarrierC64.bas",987
	DECLE 5183,32
	;[988] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",988
	DECLE 16191,63
	;[989] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",989
	DECLE 16191,63
	;[990] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",990
	DECLE 16191,63
	;[991] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",991
	DECLE 6975,63
	;[992] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",992
	DECLE 16191,63
	;[993] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",993
	DECLE 16191,63
	;[994] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",994
	DECLE 16191,63
	;[995] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",995
	DECLE 6463,63
	;[996] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",996
	DECLE 16191,63
	;[997] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",997
	DECLE 16191,63
	;[998] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",998
	DECLE 16191,63
	;[999] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",999
	DECLE 6975,63
	;[1000] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1000
	DECLE 16191,63
	;[1001] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1001
	DECLE 16191,63
	;[1002] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1002
	DECLE 16191,63
	;[1003] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1003
	DECLE 5951,63
	;[1004] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1004
	DECLE 16191,63
	;[1005] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1005
	DECLE 16191,63
	;[1006] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1006
	DECLE 16191,63
	;[1007] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1007
	DECLE 6975,63
	;[1008] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1008
	DECLE 16191,63
	;[1009] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1009
	DECLE 16191,63
	;[1010] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1010
	DECLE 16191,63
	;[1011] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1011
	DECLE 5695,63
	;[1012] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1012
	DECLE 16191,63
	;[1013] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1013
	DECLE 16191,63
	;[1014] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1014
	DECLE 16191,63
	;[1015] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1015
	DECLE 6975,63
	;[1016] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1016
	DECLE 16191,63
	;[1017] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1017
	DECLE 16191,63
	;[1018] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1018
	DECLE 16191,63
	;[1019] MUSIC s,D3,A4
	SRCFILE "Songs\SHarrierC64.bas",1019
	DECLE 3903,34
	;[1020] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1020
	DECLE 16143,63
	;[1021] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1021
	DECLE 16191,63
	;[1022] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1022
	DECLE 16191,63
	;[1023] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1023
	DECLE 6975,63
	;[1024] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1024
	DECLE 16191,63
	;[1025] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1025
	DECLE 16191,63
	;[1026] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1026
	DECLE 16191,63
	;[1027] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1027
	DECLE 6463,63
	;[1028] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1028
	DECLE 16191,63
	;[1029] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1029
	DECLE 16191,63
	;[1030] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1030
	DECLE 16191,63
	;[1031] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1031
	DECLE 6975,63
	;[1032] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1032
	DECLE 16191,63
	;[1033] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1033
	DECLE 16191,63
	;[1034] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1034
	DECLE 16191,63
	;[1035] MUSIC s,A3,F5#
	SRCFILE "Songs\SHarrierC64.bas",1035
	DECLE 5695,43
	;[1036] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1036
	DECLE 16143,63
	;[1037] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1037
	DECLE 16191,63
	;[1038] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1038
	DECLE 16191,63
	;[1039] 
	SRCFILE "Songs\SHarrierC64.bas",1039
	;[1040] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1040
	DECLE 6975,63
	;[1041] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1041
	DECLE 16191,63
	;[1042] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1042
	DECLE 16191,63
	;[1043] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1043
	DECLE 16191,63
	;[1044] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1044
	DECLE 6463,63
	;[1045] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1045
	DECLE 16191,63
	;[1046] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1046
	DECLE 16191,63
	;[1047] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1047
	DECLE 16191,63
	;[1048] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1048
	DECLE 6975,63
	;[1049] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1049
	DECLE 16191,63
	;[1050] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1050
	DECLE 16191,63
	;[1051] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1051
	DECLE 16191,63
	;[1052] MUSIC s,G3,D5
	SRCFILE "Songs\SHarrierC64.bas",1052
	DECLE 5183,39
	;[1053] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1053
	DECLE 16136,63
	;[1054] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1054
	DECLE 16191,63
	;[1055] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1055
	DECLE 16191,63
	;[1056] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1056
	DECLE 6975,35
	;[1057] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1057
	DECLE 16191,63
	;[1058] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1058
	DECLE 16191,63
	;[1059] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1059
	DECLE 16191,63
	;[1060] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",1060
	DECLE 6463,34
	;[1061] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1061
	DECLE 16148,63
	;[1062] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1062
	DECLE 16191,63
	;[1063] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1063
	DECLE 16191,63
	;[1064] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1064
	DECLE 6975,35
	;[1065] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1065
	DECLE 16191,63
	;[1066] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1066
	DECLE 16191,63
	;[1067] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1067
	DECLE 16191,63
	;[1068] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",1068
	DECLE 5951,32
	;[1069] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1069
	DECLE 16136,63
	;[1070] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1070
	DECLE 16191,63
	;[1071] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1071
	DECLE 16191,63
	;[1072] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1072
	DECLE 6975,35
	;[1073] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1073
	DECLE 16191,63
	;[1074] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1074
	DECLE 16191,63
	;[1075] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1075
	DECLE 16191,63
	;[1076] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",1076
	DECLE 6463,34
	;[1077] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1077
	DECLE 16148,63
	;[1078] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1078
	DECLE 16191,63
	;[1079] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1079
	DECLE 16191,63
	;[1080] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1080
	DECLE 6975,35
	;[1081] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1081
	DECLE 16191,63
	;[1082] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1082
	DECLE 16191,63
	;[1083] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1083
	DECLE 16191,63
	;[1084] MUSIC s,G3,D5
	SRCFILE "Songs\SHarrierC64.bas",1084
	DECLE 5183,39
	;[1085] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1085
	DECLE 16136,63
	;[1086] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1086
	DECLE 16191,63
	;[1087] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1087
	DECLE 16191,63
	;[1088] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1088
	DECLE 6975,35
	;[1089] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1089
	DECLE 16191,63
	;[1090] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1090
	DECLE 16191,63
	;[1091] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1091
	DECLE 16191,63
	;[1092] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",1092
	DECLE 6463,34
	;[1093] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1093
	DECLE 16148,63
	;[1094] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1094
	DECLE 16191,63
	;[1095] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1095
	DECLE 16191,63
	;[1096] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1096
	DECLE 6975,35
	;[1097] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1097
	DECLE 16191,63
	;[1098] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1098
	DECLE 16191,63
	;[1099] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1099
	DECLE 16191,63
	;[1100] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",1100
	DECLE 5951,32
	;[1101] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1101
	DECLE 16136,63
	;[1102] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1102
	DECLE 16191,63
	;[1103] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1103
	DECLE 16191,63
	;[1104] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1104
	DECLE 6975,35
	;[1105] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1105
	DECLE 16191,63
	;[1106] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1106
	DECLE 16191,63
	;[1107] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1107
	DECLE 16191,63
	;[1108] MUSIC s,C4,A4
	SRCFILE "Songs\SHarrierC64.bas",1108
	DECLE 6463,34
	;[1109] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1109
	DECLE 16148,63
	;[1110] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1110
	DECLE 16191,63
	;[1111] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1111
	DECLE 16191,63
	;[1112] MUSIC s,D4,A4#
	SRCFILE "Songs\SHarrierC64.bas",1112
	DECLE 6975,35
	;[1113] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1113
	DECLE 16191,63
	;[1114] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1114
	DECLE 16191,63
	;[1115] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1115
	DECLE 16191,63
	;[1116] MUSIC s,G3,D5#
	SRCFILE "Songs\SHarrierC64.bas",1116
	DECLE 5183,40
	;[1117] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1117
	DECLE 16136,63
	;[1118] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1118
	DECLE 16191,63
	;[1119] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1119
	DECLE 16191,63
	;[1120] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1120
	DECLE 7231,37
	;[1121] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1121
	DECLE 16191,63
	;[1122] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1122
	DECLE 16191,63
	;[1123] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1123
	DECLE 16191,63
	;[1124] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",1124
	DECLE 6975,36
	;[1125] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1125
	DECLE 16148,63
	;[1126] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1126
	DECLE 16191,63
	;[1127] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1127
	DECLE 16191,63
	;[1128] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1128
	DECLE 7231,37
	;[1129] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1129
	DECLE 16191,63
	;[1130] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1130
	DECLE 16191,63
	;[1131] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1131
	DECLE 16191,63
	;[1132] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1132
	DECLE 6463,32
	;[1133] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1133
	DECLE 16136,63
	;[1134] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1134
	DECLE 16191,63
	;[1135] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1135
	DECLE 16191,63
	;[1136] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1136
	DECLE 7231,37
	;[1137] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1137
	DECLE 16191,63
	;[1138] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1138
	DECLE 16191,63
	;[1139] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1139
	DECLE 16191,63
	;[1140] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",1140
	DECLE 6975,36
	;[1141] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1141
	DECLE 16148,63
	;[1142] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1142
	DECLE 16191,63
	;[1143] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1143
	DECLE 16191,63
	;[1144] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1144
	DECLE 7231,37
	;[1145] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1145
	DECLE 16191,63
	;[1146] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1146
	DECLE 16191,63
	;[1147] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1147
	DECLE 16191,63
	;[1148] MUSIC s,G3,D5#
	SRCFILE "Songs\SHarrierC64.bas",1148
	DECLE 5183,40
	;[1149] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1149
	DECLE 16136,63
	;[1150] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1150
	DECLE 16191,63
	;[1151] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1151
	DECLE 16191,63
	;[1152] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1152
	DECLE 7231,37
	;[1153] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1153
	DECLE 16191,63
	;[1154] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1154
	DECLE 16191,63
	;[1155] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1155
	DECLE 16191,63
	;[1156] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",1156
	DECLE 6975,36
	;[1157] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1157
	DECLE 16148,63
	;[1158] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1158
	DECLE 16191,63
	;[1159] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1159
	DECLE 16191,63
	;[1160] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1160
	DECLE 7231,37
	;[1161] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1161
	DECLE 16191,63
	;[1162] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1162
	DECLE 16191,63
	;[1163] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1163
	DECLE 16191,63
	;[1164] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1164
	DECLE 6463,32
	;[1165] MUSIC G2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1165
	DECLE 16136,63
	;[1166] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1166
	DECLE 16191,63
	;[1167] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1167
	DECLE 16191,63
	;[1168] 
	SRCFILE "Songs\SHarrierC64.bas",1168
	;[1169] '--------
	SRCFILE "Songs\SHarrierC64.bas",1169
	;[1170] 
	SRCFILE "Songs\SHarrierC64.bas",1170
	;[1171] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1171
	DECLE 7231,37
	;[1172] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1172
	DECLE 16191,63
	;[1173] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1173
	DECLE 16191,63
	;[1174] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1174
	DECLE 16191,63
	;[1175] MUSIC s,D4,B4
	SRCFILE "Songs\SHarrierC64.bas",1175
	DECLE 6975,36
	;[1176] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1176
	DECLE 16148,63
	;[1177] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1177
	DECLE 16191,63
	;[1178] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1178
	DECLE 16191,63
	;[1179] MUSIC s,D4#,C5
	SRCFILE "Songs\SHarrierC64.bas",1179
	DECLE 7231,37
	;[1180] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1180
	DECLE 16191,63
	;[1181] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1181
	DECLE 16191,63
	;[1182] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1182
	DECLE 16191,63
	;[1183] MUSIC s,F3#,D5
	SRCFILE "Songs\SHarrierC64.bas",1183
	DECLE 4927,39
	;[1184] MUSIC F2#,s,s
	SRCFILE "Songs\SHarrierC64.bas",1184
	DECLE 16135,63
	;[1185] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1185
	DECLE 16191,63
	;[1186] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1186
	DECLE 16191,63
	;[1187] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",1187
	DECLE 6975,34
	;[1188] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1188
	DECLE 16191,63
	;[1189] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1189
	DECLE 16191,63
	;[1190] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1190
	DECLE 16191,63
	;[1191] 
	SRCFILE "Songs\SHarrierC64.bas",1191
	;[1192] MUSIC F3#,C4,G4	'<-- fixed?
	SRCFILE "Songs\SHarrierC64.bas",1192
	DECLE 6419,32
	;[1193] 
	SRCFILE "Songs\SHarrierC64.bas",1193
	;[1194] MUSIC s,s,s		
	SRCFILE "Songs\SHarrierC64.bas",1194
	DECLE 16191,63
	;[1195] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1195
	DECLE 16191,63
	;[1196] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1196
	DECLE 16191,63
	;[1197] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",1197
	DECLE 6975,34
	;[1198] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1198
	DECLE 16191,63
	;[1199] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1199
	DECLE 16191,63
	;[1200] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1200
	DECLE 16191,63
	;[1201] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1201
	DECLE 16191,31
	;[1202] MUSIC F2#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1202
	DECLE 5639,63
	;[1203] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1203
	DECLE 16191,63
	;[1204] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1204
	DECLE 16191,63
	;[1205] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1205
	DECLE 16191,34
	;[1206] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1206
	DECLE 6975,63
	;[1207] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1207
	DECLE 16191,63
	;[1208] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1208
	DECLE 16191,63
	;[1209] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1209
	DECLE 16191,32
	;[1210] MUSIC F3#,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1210
	DECLE 6419,63
	;[1211] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1211
	DECLE 16191,63
	;[1212] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1212
	DECLE 16191,63
	;[1213] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",1213
	DECLE 6975,34
	;[1214] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1214
	DECLE 16191,63
	;[1215] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1215
	DECLE 16191,63
	;[1216] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1216
	DECLE 16191,63
	;[1217] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1217
	DECLE 16191,39
	;[1218] MUSIC F2#,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",1218
	DECLE 4871,63
	;[1219] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1219
	DECLE 16191,63
	;[1220] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1220
	DECLE 16191,63
	;[1221] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",1221
	DECLE 6975,34
	;[1222] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1222
	DECLE 16191,63
	;[1223] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1223
	DECLE 16191,63
	;[1224] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1224
	DECLE 16191,63
	;[1225] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1225
	DECLE 16191,32
	;[1226] MUSIC F3#,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1226
	DECLE 6419,63
	;[1227] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1227
	DECLE 16191,63
	;[1228] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1228
	DECLE 16191,63
	;[1229] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",1229
	DECLE 6975,34
	;[1230] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1230
	DECLE 16191,63
	;[1231] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1231
	DECLE 16191,63
	;[1232] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1232
	DECLE 16191,63
	;[1233] MUSIC s,A3,F4#
	SRCFILE "Songs\SHarrierC64.bas",1233
	DECLE 5695,31
	;[1234] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1234
	DECLE 16143,63
	;[1235] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1235
	DECLE 16191,63
	;[1236] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1236
	DECLE 16191,63
	;[1237] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",1237
	DECLE 6975,34
	;[1238] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1238
	DECLE 16191,63
	;[1239] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1239
	DECLE 16191,63
	;[1240] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1240
	DECLE 16191,63
	;[1241] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1241
	DECLE 6463,32
	;[1242] MUSIC D3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1242
	DECLE 16143,63
	;[1243] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1243
	DECLE 16191,63
	;[1244] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1244
	DECLE 16191,63
	;[1245] MUSIC s,D4,A4
	SRCFILE "Songs\SHarrierC64.bas",1245
	DECLE 6975,34
	;[1246] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1246
	DECLE 16191,63
	;[1247] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1247
	DECLE 16191,63
	;[1248] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1248
	DECLE 16191,63
	;[1249] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1249
	DECLE 16191,35
	;[1250] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1250
	DECLE 5128,63
	;[1251] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1251
	DECLE 16191,63
	;[1252] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1252
	DECLE 16191,63
	;[1253] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",1253
	DECLE 6975,32
	;[1254] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1254
	DECLE 16191,63
	;[1255] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1255
	DECLE 16191,63
	;[1256] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1256
	DECLE 16191,63
	;[1257] MUSIC s,C4,F4#
	SRCFILE "Songs\SHarrierC64.bas",1257
	DECLE 6463,31
	;[1258] MUSIC G3,s,s
	SRCFILE "Songs\SHarrierC64.bas",1258
	DECLE 16148,63
	;[1259] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1259
	DECLE 16191,63
	;[1260] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1260
	DECLE 16191,63
	;[1261] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",1261
	DECLE 6975,32
	;[1262] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1262
	DECLE 16191,63
	;[1263] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1263
	DECLE 16191,63
	;[1264] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1264
	DECLE 16191,63
	;[1265] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",1265
	DECLE 16191,27
	;[1266] MUSIC G2,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1266
	DECLE 5896,63
	;[1267] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1267
	DECLE 16191,63
	;[1268] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1268
	DECLE 16191,63
	;[1269] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",1269
	DECLE 6975,32
	;[1270] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1270
	DECLE 16191,63
	;[1271] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1271
	DECLE 16191,63
	;[1272] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1272
	DECLE 16191,63
	;[1273] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1273
	DECLE 16191,31
	;[1274] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1274
	DECLE 6420,63
	;[1275] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1275
	DECLE 16191,63
	;[1276] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1276
	DECLE 16191,63
	;[1277] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",1277
	DECLE 6975,32
	;[1278] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1278
	DECLE 16191,63
	;[1279] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1279
	DECLE 16191,63
	;[1280] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1280
	DECLE 16191,63
	;[1281] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1281
	DECLE 16191,35
	;[1282] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1282
	DECLE 5128,63
	;[1283] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1283
	DECLE 16191,63
	;[1284] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1284
	DECLE 16191,63
	;[1285] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",1285
	DECLE 6975,32
	;[1286] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1286
	DECLE 16191,63
	;[1287] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1287
	DECLE 16191,63
	;[1288] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1288
	DECLE 16191,63
	;[1289] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1289
	DECLE 16191,31
	;[1290] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1290
	DECLE 6420,63
	;[1291] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1291
	DECLE 16191,63
	;[1292] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1292
	DECLE 16191,63
	;[1293] MUSIC s,D4,G4
	SRCFILE "Songs\SHarrierC64.bas",1293
	DECLE 6975,32
	;[1294] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1294
	DECLE 16191,63
	;[1295] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1295
	DECLE 16191,63
	;[1296] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1296
	DECLE 16191,63
	;[1297] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",1297
	DECLE 16191,27
	;[1298] MUSIC G2,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1298
	DECLE 5896,63
	;[1299] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1299
	DECLE 16191,63
	;[1300] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1300
	DECLE 16191,63
	;[1301] 
	SRCFILE "Songs\SHarrierC64.bas",1301
	;[1302] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1302
	DECLE 16191,32
	;[1303] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1303
	DECLE 6975,63
	;[1304] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1304
	DECLE 16191,63
	;[1305] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1305
	DECLE 16191,63
	;[1306] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1306
	DECLE 16191,31
	;[1307] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1307
	DECLE 6420,63
	;[1308] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1308
	DECLE 16191,63
	;[1309] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1309
	DECLE 16191,63
	;[1310] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1310
	DECLE 16191,32
	;[1311] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1311
	DECLE 6975,63
	;[1312] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1312
	DECLE 16191,63
	;[1313] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1313
	DECLE 16191,63
	;[1314] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1314
	DECLE 16191,37
	;[1315] MUSIC D3#,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1315
	DECLE 4112,63
	;[1316] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1316
	DECLE 16191,63
	;[1317] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1317
	DECLE 16191,63
	;[1318] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1318
	DECLE 16191,32
	;[1319] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1319
	DECLE 6463,63
	;[1320] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1320
	DECLE 16191,63
	;[1321] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1321
	DECLE 16191,63
	;[1322] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1322
	DECLE 16191,31
	;[1323] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1323
	DECLE 5648,63
	;[1324] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1324
	DECLE 16191,63
	;[1325] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1325
	DECLE 16191,63
	;[1326] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1326
	DECLE 6463,32
	;[1327] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1327
	DECLE 16191,63
	;[1328] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1328
	DECLE 16191,63
	;[1329] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1329
	DECLE 16191,63
	;[1330] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",1330
	DECLE 16191,28
	;[1331] MUSIC D3#,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1331
	DECLE 5136,63
	;[1332] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1332
	DECLE 16191,63
	;[1333] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1333
	DECLE 16191,63
	;[1334] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1334
	DECLE 6463,32
	;[1335] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1335
	DECLE 16191,63
	;[1336] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1336
	DECLE 16191,63
	;[1337] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1337
	DECLE 16191,63
	;[1338] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1338
	DECLE 16191,31
	;[1339] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1339
	DECLE 5648,63
	;[1340] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1340
	DECLE 16191,63
	;[1341] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1341
	DECLE 16191,63
	;[1342] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1342
	DECLE 6463,32
	;[1343] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1343
	DECLE 16191,63
	;[1344] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1344
	DECLE 16191,63
	;[1345] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1345
	DECLE 16191,63
	;[1346] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1346
	DECLE 16191,37
	;[1347] MUSIC D3#,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1347
	DECLE 4112,63
	;[1348] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1348
	DECLE 16191,63
	;[1349] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1349
	DECLE 16191,63
	;[1350] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1350
	DECLE 6463,32
	;[1351] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1351
	DECLE 16191,63
	;[1352] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1352
	DECLE 16191,63
	;[1353] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1353
	DECLE 16191,63
	;[1354] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1354
	DECLE 16191,31
	;[1355] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1355
	DECLE 5648,63
	;[1356] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1356
	DECLE 16191,63
	;[1357] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1357
	DECLE 16191,63
	;[1358] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1358
	DECLE 16191,32
	;[1359] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1359
	DECLE 6463,63
	;[1360] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1360
	DECLE 16191,63
	;[1361] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1361
	DECLE 16191,63
	;[1362] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",1362
	DECLE 16191,28
	;[1363] MUSIC D3#,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1363
	DECLE 5136,63
	;[1364] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1364
	DECLE 16191,63
	;[1365] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1365
	DECLE 16191,63
	;[1366] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1366
	DECLE 16191,32
	;[1367] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1367
	DECLE 6463,63
	;[1368] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1368
	DECLE 16191,63
	;[1369] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1369
	DECLE 16191,63
	;[1370] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1370
	DECLE 16191,31
	;[1371] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1371
	DECLE 5648,63
	;[1372] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1372
	DECLE 16191,63
	;[1373] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1373
	DECLE 16191,63
	;[1374] MUSIC s,C4,G4
	SRCFILE "Songs\SHarrierC64.bas",1374
	DECLE 6463,32
	;[1375] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1375
	DECLE 16191,63
	;[1376] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1376
	DECLE 16191,63
	;[1377] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1377
	DECLE 16191,63
	;[1378] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1378
	DECLE 16191,35
	;[1379] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",1379
	DECLE 3855,63
	;[1380] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1380
	DECLE 16191,63
	;[1381] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1381
	DECLE 16191,63
	;[1382] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1382
	DECLE 16191,32
	;[1383] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1383
	DECLE 5951,63
	;[1384] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1384
	DECLE 16191,63
	;[1385] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1385
	DECLE 16191,63
	;[1386] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1386
	DECLE 16191,31
	;[1387] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1387
	DECLE 5647,63
	;[1388] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1388
	DECLE 16191,63
	;[1389] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1389
	DECLE 16191,63
	;[1390] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1390
	DECLE 16191,32
	;[1391] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1391
	DECLE 5951,63
	;[1392] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1392
	DECLE 16191,63
	;[1393] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1393
	DECLE 16191,63
	;[1394] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",1394
	DECLE 16191,27
	;[1395] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1395
	DECLE 5135,63
	;[1396] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1396
	DECLE 16191,63
	;[1397] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1397
	DECLE 16191,63
	;[1398] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1398
	DECLE 16191,32
	;[1399] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1399
	DECLE 5951,63
	;[1400] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1400
	DECLE 16191,63
	;[1401] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1401
	DECLE 16191,63
	;[1402] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1402
	DECLE 16191,31
	;[1403] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1403
	DECLE 5647,63
	;[1404] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1404
	DECLE 16191,63
	;[1405] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1405
	DECLE 16191,63
	;[1406] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1406
	DECLE 16191,32
	;[1407] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1407
	DECLE 5951,63
	;[1408] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1408
	DECLE 16191,63
	;[1409] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1409
	DECLE 16191,63
	;[1410] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1410
	DECLE 16191,35
	;[1411] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",1411
	DECLE 3855,63
	;[1412] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1412
	DECLE 16191,63
	;[1413] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1413
	DECLE 16191,63
	;[1414] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",1414
	DECLE 5951,32
	;[1415] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1415
	DECLE 16191,63
	;[1416] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1416
	DECLE 16191,63
	;[1417] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1417
	DECLE 16191,63
	;[1418] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1418
	DECLE 16191,31
	;[1419] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1419
	DECLE 5647,63
	;[1420] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1420
	DECLE 16191,63
	;[1421] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1421
	DECLE 16191,63
	;[1422] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",1422
	DECLE 5951,32
	;[1423] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1423
	DECLE 16191,63
	;[1424] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1424
	DECLE 16191,63
	;[1425] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1425
	DECLE 16191,63
	;[1426] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",1426
	DECLE 16191,27
	;[1427] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1427
	DECLE 5135,63
	;[1428] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1428
	DECLE 16191,63
	;[1429] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1429
	DECLE 16191,63
	;[1430] 
	SRCFILE "Songs\SHarrierC64.bas",1430
	;[1431] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",1431
	DECLE 5951,32
	;[1432] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1432
	DECLE 16191,63
	;[1433] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1433
	DECLE 16191,63
	;[1434] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1434
	DECLE 16191,63
	;[1435] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1435
	DECLE 16191,31
	;[1436] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1436
	DECLE 5647,63
	;[1437] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1437
	DECLE 16191,63
	;[1438] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1438
	DECLE 16191,63
	;[1439] MUSIC s,A3#,G4
	SRCFILE "Songs\SHarrierC64.bas",1439
	DECLE 5951,32
	;[1440] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1440
	DECLE 16191,63
	;[1441] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1441
	DECLE 16191,63
	;[1442] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1442
	DECLE 16191,63
	;[1443] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1443
	DECLE 16191,34
	;[1444] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",1444
	DECLE 3855,63
	;[1445] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1445
	DECLE 16191,63
	;[1446] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1446
	DECLE 16191,63
	;[1447] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1447
	DECLE 16191,31
	;[1448] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1448
	DECLE 5695,63
	;[1449] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1449
	DECLE 16191,63
	;[1450] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1450
	DECLE 16191,63
	;[1451] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",1451
	DECLE 16191,29
	;[1452] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1452
	DECLE 5135,63
	;[1453] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1453
	DECLE 16191,63
	;[1454] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1454
	DECLE 16191,63
	;[1455] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1455
	DECLE 16191,31
	;[1456] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1456
	DECLE 5695,63
	;[1457] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1457
	DECLE 16191,63
	;[1458] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1458
	DECLE 16191,63
	;[1459] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",1459
	DECLE 16191,27
	;[1460] MUSIC D3,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",1460
	DECLE 4879,63
	;[1461] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1461
	DECLE 16191,63
	;[1462] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1462
	DECLE 16191,63
	;[1463] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1463
	DECLE 16191,31
	;[1464] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1464
	DECLE 5695,63
	;[1465] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1465
	DECLE 16191,63
	;[1466] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1466
	DECLE 16191,63
	;[1467] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",1467
	DECLE 16191,29
	;[1468] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1468
	DECLE 5135,63
	;[1469] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1469
	DECLE 16191,63
	;[1470] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1470
	DECLE 16191,63
	;[1471] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1471
	DECLE 16191,31
	;[1472] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1472
	DECLE 5695,63
	;[1473] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1473
	DECLE 16191,63
	;[1474] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1474
	DECLE 16191,63
	;[1475] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1475
	DECLE 16191,34
	;[1476] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",1476
	DECLE 3855,63
	;[1477] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1477
	DECLE 16191,63
	;[1478] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1478
	DECLE 16191,63
	;[1479] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1479
	DECLE 16191,31
	;[1480] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1480
	DECLE 5695,63
	;[1481] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1481
	DECLE 16191,63
	;[1482] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1482
	DECLE 16191,63
	;[1483] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",1483
	DECLE 16191,29
	;[1484] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1484
	DECLE 5135,63
	;[1485] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1485
	DECLE 16191,63
	;[1486] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1486
	DECLE 16191,63
	;[1487] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1487
	DECLE 16191,31
	;[1488] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1488
	DECLE 5695,63
	;[1489] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1489
	DECLE 16191,63
	;[1490] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1490
	DECLE 16191,63
	;[1491] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",1491
	DECLE 16191,27
	;[1492] MUSIC D3,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",1492
	DECLE 4879,63
	;[1493] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1493
	DECLE 16191,63
	;[1494] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1494
	DECLE 16191,63
	;[1495] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1495
	DECLE 16191,31
	;[1496] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1496
	DECLE 5695,63
	;[1497] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1497
	DECLE 16191,63
	;[1498] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1498
	DECLE 16191,63
	;[1499] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",1499
	DECLE 16191,29
	;[1500] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1500
	DECLE 5135,63
	;[1501] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1501
	DECLE 16191,63
	;[1502] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1502
	DECLE 16191,63
	;[1503] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1503
	DECLE 16191,31
	;[1504] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1504
	DECLE 5695,63
	;[1505] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1505
	DECLE 16191,63
	;[1506] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1506
	DECLE 16191,63
	;[1507] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1507
	DECLE 16191,32
	;[1508] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1508
	DECLE 5183,63
	;[1509] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1509
	DECLE 16191,63
	;[1510] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1510
	DECLE 16191,63
	;[1511] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1511
	DECLE 6975,63
	;[1512] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1512
	DECLE 16191,63
	;[1513] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1513
	DECLE 16191,63
	;[1514] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1514
	DECLE 16191,63
	;[1515] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1515
	DECLE 6463,63
	;[1516] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1516
	DECLE 16191,63
	;[1517] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1517
	DECLE 16191,63
	;[1518] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1518
	DECLE 16191,63
	;[1519] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1519
	DECLE 6975,63
	;[1520] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1520
	DECLE 16191,63
	;[1521] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1521
	DECLE 16191,63
	;[1522] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1522
	DECLE 16191,63
	;[1523] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1523
	DECLE 5951,63
	;[1524] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1524
	DECLE 16191,63
	;[1525] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1525
	DECLE 16191,63
	;[1526] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1526
	DECLE 16191,63
	;[1527] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1527
	DECLE 6975,63
	;[1528] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1528
	DECLE 16191,63
	;[1529] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1529
	DECLE 16191,63
	;[1530] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1530
	DECLE 16191,63
	;[1531] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1531
	DECLE 5695,63
	;[1532] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1532
	DECLE 16191,63
	;[1533] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1533
	DECLE 16191,63
	;[1534] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1534
	DECLE 16191,63
	;[1535] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1535
	DECLE 6975,63
	;[1536] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1536
	DECLE 16191,63
	;[1537] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1537
	DECLE 16191,63
	;[1538] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1538
	DECLE 16191,63
	;[1539] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1539
	DECLE 16191,34
	;[1540] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",1540
	DECLE 3855,63
	;[1541] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1541
	DECLE 16191,63
	;[1542] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1542
	DECLE 16191,63
	;[1543] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1543
	DECLE 6975,63
	;[1544] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1544
	DECLE 16191,63
	;[1545] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1545
	DECLE 16191,63
	;[1546] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1546
	DECLE 16191,63
	;[1547] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1547
	DECLE 6463,63
	;[1548] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1548
	DECLE 16191,63
	;[1549] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1549
	DECLE 16191,63
	;[1550] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1550
	DECLE 16191,63
	;[1551] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1551
	DECLE 6975,63
	;[1552] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1552
	DECLE 16191,63
	;[1553] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1553
	DECLE 16191,63
	;[1554] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1554
	DECLE 16191,63
	;[1555] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",1555
	DECLE 16191,43
	;[1556] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1556
	DECLE 5647,63
	;[1557] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1557
	DECLE 16191,63
	;[1558] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1558
	DECLE 16191,63
	;[1559] 
	SRCFILE "Songs\SHarrierC64.bas",1559
	;[1560] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1560
	DECLE 6975,63
	;[1561] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1561
	DECLE 16191,63
	;[1562] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1562
	DECLE 16191,63
	;[1563] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1563
	DECLE 16191,63
	;[1564] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1564
	DECLE 6463,63
	;[1565] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1565
	DECLE 16191,63
	;[1566] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1566
	DECLE 16191,63
	;[1567] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1567
	DECLE 16191,63
	;[1568] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1568
	DECLE 6975,63
	;[1569] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1569
	DECLE 16191,63
	;[1570] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1570
	DECLE 16191,63
	;[1571] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1571
	DECLE 16191,63
	;[1572] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",1572
	DECLE 16191,40
	;[1573] MUSIC C3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1573
	DECLE 6413,63
	;[1574] MUSIC s,s,D6#
	SRCFILE "Songs\SHarrierC64.bas",1574
	DECLE 16191,52
	;[1575] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",1575
	DECLE 16191,40
	;[1576] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1576
	DECLE 16191,37
	;[1577] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1577
	DECLE 8255,63
	;[1578] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1578
	DECLE 16191,49
	;[1579] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1579
	DECLE 16191,37
	;[1580] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1580
	DECLE 16191,36
	;[1581] MUSIC C3,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1581
	DECLE 7693,63
	;[1582] MUSIC s,s,B5
	SRCFILE "Songs\SHarrierC64.bas",1582
	DECLE 16191,48
	;[1583] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1583
	DECLE 16191,36
	;[1584] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1584
	DECLE 16191,37
	;[1585] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1585
	DECLE 8255,63
	;[1586] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1586
	DECLE 16191,49
	;[1587] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1587
	DECLE 16191,37
	;[1588] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1588
	DECLE 16191,32
	;[1589] MUSIC C3,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",1589
	DECLE 7181,63
	;[1590] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1590
	DECLE 16191,44
	;[1591] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1591
	DECLE 16191,32
	;[1592] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1592
	DECLE 16191,37
	;[1593] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1593
	DECLE 8255,63
	;[1594] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1594
	DECLE 16191,49
	;[1595] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1595
	DECLE 16191,37
	;[1596] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1596
	DECLE 16191,36
	;[1597] MUSIC C3,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1597
	DECLE 7693,63
	;[1598] MUSIC s,s,B5
	SRCFILE "Songs\SHarrierC64.bas",1598
	DECLE 16191,48
	;[1599] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1599
	DECLE 16191,36
	;[1600] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1600
	DECLE 16191,37
	;[1601] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1601
	DECLE 8255,63
	;[1602] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1602
	DECLE 16191,49
	;[1603] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1603
	DECLE 16191,37
	;[1604] MUSIC s,F3,s
	SRCFILE "Songs\SHarrierC64.bas",1604
	DECLE 4671,63
	;[1605] MUSIC F2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1605
	DECLE 16134,63
	;[1606] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1606
	DECLE 16191,49
	;[1607] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1607
	DECLE 16191,37
	;[1608] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1608
	DECLE 16191,34
	;[1609] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1609
	DECLE 6463,63
	;[1610] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1610
	DECLE 16191,46
	;[1611] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1611
	DECLE 16191,34
	;[1612] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1612
	DECLE 16191,32
	;[1613] MUSIC F3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1613
	DECLE 5906,63
	;[1614] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1614
	DECLE 16191,44
	;[1615] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1615
	DECLE 16191,32
	;[1616] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1616
	DECLE 16191,34
	;[1617] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1617
	DECLE 6463,63
	;[1618] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1618
	DECLE 16191,46
	;[1619] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1619
	DECLE 16191,34
	;[1620] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1620
	DECLE 16191,30
	;[1621] MUSIC F2,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1621
	DECLE 5638,63
	;[1622] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1622
	DECLE 16191,42
	;[1623] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1623
	DECLE 16191,30
	;[1624] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1624
	DECLE 16191,34
	;[1625] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1625
	DECLE 6463,63
	;[1626] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1626
	DECLE 16191,46
	;[1627] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1627
	DECLE 16191,34
	;[1628] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1628
	DECLE 16191,32
	;[1629] MUSIC F3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1629
	DECLE 5906,63
	;[1630] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1630
	DECLE 16191,44
	;[1631] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1631
	DECLE 16191,32
	;[1632] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1632
	DECLE 16191,34
	;[1633] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1633
	DECLE 6463,63
	;[1634] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1634
	DECLE 16191,46
	;[1635] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1635
	DECLE 16191,34
	;[1636] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1636
	DECLE 16191,39
	;[1637] MUSIC A2#,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1637
	DECLE 5899,63
	;[1638] MUSIC s,s,D6
	SRCFILE "Songs\SHarrierC64.bas",1638
	DECLE 16191,51
	;[1639] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1639
	DECLE 16191,39
	;[1640] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1640
	DECLE 16191,35
	;[1641] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1641
	DECLE 7743,63
	;[1642] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1642
	DECLE 16191,47
	;[1643] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1643
	DECLE 16191,35
	;[1644] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1644
	DECLE 16191,34
	;[1645] MUSIC A3#,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",1645
	DECLE 7191,63
	;[1646] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1646
	DECLE 16191,46
	;[1647] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1647
	DECLE 16191,34
	;[1648] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1648
	DECLE 16191,35
	;[1649] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1649
	DECLE 7743,63
	;[1650] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1650
	DECLE 16191,47
	;[1651] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1651
	DECLE 16191,35
	;[1652] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1652
	DECLE 16191,30
	;[1653] MUSIC A2#,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1653
	DECLE 6923,63
	;[1654] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1654
	DECLE 16191,42
	;[1655] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1655
	DECLE 16191,30
	;[1656] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1656
	DECLE 16191,35
	;[1657] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1657
	DECLE 7743,63
	;[1658] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1658
	DECLE 16191,47
	;[1659] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1659
	DECLE 16191,35
	;[1660] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1660
	DECLE 16191,34
	;[1661] MUSIC A3#,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",1661
	DECLE 7191,63
	;[1662] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1662
	DECLE 16191,46
	;[1663] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1663
	DECLE 16191,34
	;[1664] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1664
	DECLE 16191,35
	;[1665] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1665
	DECLE 7743,63
	;[1666] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1666
	DECLE 16191,47
	;[1667] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1667
	DECLE 16191,35
	;[1668] MUSIC s,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1668
	DECLE 4159,63
	;[1669] MUSIC D3#,s,s
	SRCFILE "Songs\SHarrierC64.bas",1669
	DECLE 16144,63
	;[1670] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1670
	DECLE 16191,47
	;[1671] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1671
	DECLE 16191,35
	;[1672] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1672
	DECLE 16191,32
	;[1673] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1673
	DECLE 5951,63
	;[1674] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1674
	DECLE 16191,44
	;[1675] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1675
	DECLE 16191,32
	;[1676] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1676
	DECLE 16191,30
	;[1677] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1677
	DECLE 5648,63
	;[1678] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1678
	DECLE 16191,42
	;[1679] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1679
	DECLE 16191,30
	;[1680] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1680
	DECLE 16191,32
	;[1681] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1681
	DECLE 5951,63
	;[1682] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1682
	DECLE 16191,44
	;[1683] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1683
	DECLE 16191,32
	;[1684] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",1684
	DECLE 16191,28
	;[1685] MUSIC D3#,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1685
	DECLE 5136,63
	;[1686] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",1686
	DECLE 16191,40
	;[1687] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",1687
	DECLE 16191,28
	;[1688] 
	SRCFILE "Songs\SHarrierC64.bas",1688
	;[1689] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1689
	DECLE 16191,32
	;[1690] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1690
	DECLE 5951,63
	;[1691] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1691
	DECLE 16191,44
	;[1692] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1692
	DECLE 16191,32
	;[1693] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1693
	DECLE 16191,30
	;[1694] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1694
	DECLE 5648,63
	;[1695] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1695
	DECLE 16191,42
	;[1696] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1696
	DECLE 16191,30
	;[1697] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1697
	DECLE 16191,32
	;[1698] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1698
	DECLE 5951,63
	;[1699] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1699
	DECLE 16191,44
	;[1700] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1700
	DECLE 16191,32
	;[1701] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1701
	DECLE 16191,37
	;[1702] MUSIC C3,C3,s
	SRCFILE "Songs\SHarrierC64.bas",1702
	DECLE 3341,63
	;[1703] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1703
	DECLE 16191,49
	;[1704] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1704
	DECLE 16191,37
	;[1705] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1705
	DECLE 16191,34
	;[1706] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1706
	DECLE 5183,63
	;[1707] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1707
	DECLE 16191,46
	;[1708] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1708
	DECLE 4927,34
	;[1709] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1709
	DECLE 16191,32
	;[1710] MUSIC C3,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1710
	DECLE 4109,63
	;[1711] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1711
	DECLE 16191,44
	;[1712] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1712
	DECLE 16191,32
	;[1713] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1713
	DECLE 16191,34
	;[1714] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1714
	DECLE 5183,63
	;[1715] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1715
	DECLE 16191,46
	;[1716] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1716
	DECLE 4927,34
	;[1717] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1717
	DECLE 16191,31
	;[1718] MUSIC C3,C3,s
	SRCFILE "Songs\SHarrierC64.bas",1718
	DECLE 3341,63
	;[1719] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",1719
	DECLE 16191,43
	;[1720] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1720
	DECLE 16191,31
	;[1721] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1721
	DECLE 16191,34
	;[1722] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1722
	DECLE 5183,63
	;[1723] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1723
	DECLE 16191,46
	;[1724] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1724
	DECLE 4927,34
	;[1725] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1725
	DECLE 16191,32
	;[1726] MUSIC C3,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1726
	DECLE 4109,63
	;[1727] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1727
	DECLE 16191,44
	;[1728] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1728
	DECLE 16191,32
	;[1729] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1729
	DECLE 16191,34
	;[1730] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1730
	DECLE 5183,63
	;[1731] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1731
	DECLE 16191,46
	;[1732] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1732
	DECLE 4927,34
	;[1733] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1733
	DECLE 16191,37
	;[1734] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",1734
	DECLE 3855,63
	;[1735] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1735
	DECLE 16191,49
	;[1736] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1736
	DECLE 16191,37
	;[1737] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1737
	DECLE 16191,34
	;[1738] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1738
	DECLE 6463,63
	;[1739] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1739
	DECLE 16191,46
	;[1740] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1740
	DECLE 16191,34
	;[1741] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1741
	DECLE 16191,32
	;[1742] MUSIC D3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1742
	DECLE 5903,63
	;[1743] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1743
	DECLE 16191,44
	;[1744] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1744
	DECLE 16191,32
	;[1745] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1745
	DECLE 16191,34
	;[1746] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1746
	DECLE 6463,63
	;[1747] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1747
	DECLE 16191,46
	;[1748] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1748
	DECLE 16191,34
	;[1749] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1749
	DECLE 16191,31
	;[1750] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1750
	DECLE 5647,63
	;[1751] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",1751
	DECLE 16191,43
	;[1752] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1752
	DECLE 16191,31
	;[1753] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1753
	DECLE 16191,34
	;[1754] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1754
	DECLE 6463,63
	;[1755] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1755
	DECLE 16191,46
	;[1756] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1756
	DECLE 16191,34
	;[1757] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1757
	DECLE 16191,32
	;[1758] MUSIC D3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1758
	DECLE 5903,63
	;[1759] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1759
	DECLE 16191,44
	;[1760] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1760
	DECLE 16191,32
	;[1761] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1761
	DECLE 16191,34
	;[1762] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1762
	DECLE 6463,63
	;[1763] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1763
	DECLE 16191,46
	;[1764] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1764
	DECLE 16191,34
	;[1765] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1765
	DECLE 16191,35
	;[1766] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1766
	DECLE 5128,63
	;[1767] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1767
	DECLE 16191,47
	;[1768] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1768
	DECLE 16191,35
	;[1769] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1769
	DECLE 16191,47
	;[1770] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1770
	DECLE 6975,63
	;[1771] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1771
	DECLE 16191,35
	;[1772] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1772
	DECLE 16191,47
	;[1773] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1773
	DECLE 16191,35
	;[1774] MUSIC G3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1774
	DECLE 5908,63
	;[1775] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1775
	DECLE 16191,47
	;[1776] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1776
	DECLE 16191,35
	;[1777] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1777
	DECLE 16191,47
	;[1778] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1778
	DECLE 6975,63
	;[1779] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1779
	DECLE 16191,35
	;[1780] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1780
	DECLE 16191,47
	;[1781] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1781
	DECLE 16191,35
	;[1782] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1782
	DECLE 5128,63
	;[1783] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1783
	DECLE 16191,47
	;[1784] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1784
	DECLE 16191,35
	;[1785] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1785
	DECLE 16191,47
	;[1786] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1786
	DECLE 6975,63
	;[1787] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1787
	DECLE 16191,35
	;[1788] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1788
	DECLE 16191,47
	;[1789] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1789
	DECLE 16191,35
	;[1790] MUSIC G3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1790
	DECLE 5908,63
	;[1791] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1791
	DECLE 16191,47
	;[1792] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1792
	DECLE 16191,35
	;[1793] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1793
	DECLE 16191,47
	;[1794] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1794
	DECLE 6975,63
	;[1795] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1795
	DECLE 16191,35
	;[1796] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1796
	DECLE 16191,47
	;[1797] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1797
	DECLE 16191,35
	;[1798] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1798
	DECLE 5183,63
	;[1799] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1799
	DECLE 16191,47
	;[1800] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1800
	DECLE 16191,35
	;[1801] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1801
	DECLE 16191,47
	;[1802] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1802
	DECLE 6975,63
	;[1803] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1803
	DECLE 16191,35
	;[1804] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1804
	DECLE 16191,47
	;[1805] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1805
	DECLE 16191,37
	;[1806] MUSIC A3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1806
	DECLE 5654,63
	;[1807] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1807
	DECLE 16191,49
	;[1808] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1808
	DECLE 16191,37
	;[1809] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1809
	DECLE 16191,49
	;[1810] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1810
	DECLE 6975,63
	;[1811] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1811
	DECLE 16191,37
	;[1812] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1812
	DECLE 16191,49
	;[1813] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1813
	DECLE 16191,39
	;[1814] MUSIC A3#,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1814
	DECLE 5911,63
	;[1815] MUSIC s,s,D6
	SRCFILE "Songs\SHarrierC64.bas",1815
	DECLE 16191,51
	;[1816] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1816
	DECLE 16191,39
	;[1817] 
	SRCFILE "Songs\SHarrierC64.bas",1817
	;[1818] MUSIC s,s,D6
	SRCFILE "Songs\SHarrierC64.bas",1818
	DECLE 16191,51
	;[1819] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1819
	DECLE 6975,63
	;[1820] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1820
	DECLE 16191,39
	;[1821] MUSIC s,s,D6
	SRCFILE "Songs\SHarrierC64.bas",1821
	DECLE 16191,51
	;[1822] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1822
	DECLE 16191,35
	;[1823] MUSIC G3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1823
	DECLE 5140,63
	;[1824] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1824
	DECLE 16191,47
	;[1825] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1825
	DECLE 16191,35
	;[1826] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1826
	DECLE 16191,47
	;[1827] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1827
	DECLE 6975,63
	;[1828] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1828
	DECLE 16191,35
	;[1829] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1829
	DECLE 16191,47
	;[1830] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",1830
	DECLE 16191,40
	;[1831] MUSIC C3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1831
	DECLE 6413,63
	;[1832] MUSIC s,s,D6#
	SRCFILE "Songs\SHarrierC64.bas",1832
	DECLE 16191,52
	;[1833] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",1833
	DECLE 16191,40
	;[1834] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1834
	DECLE 16191,37
	;[1835] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1835
	DECLE 8255,63
	;[1836] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1836
	DECLE 16191,49
	;[1837] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1837
	DECLE 16191,37
	;[1838] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1838
	DECLE 16191,36
	;[1839] MUSIC C3,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1839
	DECLE 7693,63
	;[1840] MUSIC s,s,B5
	SRCFILE "Songs\SHarrierC64.bas",1840
	DECLE 16191,48
	;[1841] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1841
	DECLE 16191,36
	;[1842] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1842
	DECLE 16191,37
	;[1843] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1843
	DECLE 8255,63
	;[1844] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1844
	DECLE 16191,49
	;[1845] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1845
	DECLE 16191,37
	;[1846] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1846
	DECLE 16191,32
	;[1847] MUSIC C3,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",1847
	DECLE 7181,63
	;[1848] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1848
	DECLE 16191,44
	;[1849] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1849
	DECLE 16191,32
	;[1850] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1850
	DECLE 16191,37
	;[1851] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1851
	DECLE 8255,63
	;[1852] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1852
	DECLE 16191,49
	;[1853] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1853
	DECLE 16191,37
	;[1854] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1854
	DECLE 16191,36
	;[1855] MUSIC C3,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1855
	DECLE 7693,63
	;[1856] MUSIC s,s,B5
	SRCFILE "Songs\SHarrierC64.bas",1856
	DECLE 16191,48
	;[1857] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",1857
	DECLE 16191,36
	;[1858] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1858
	DECLE 16191,37
	;[1859] MUSIC s,G4,s
	SRCFILE "Songs\SHarrierC64.bas",1859
	DECLE 8255,63
	;[1860] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1860
	DECLE 16191,49
	;[1861] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1861
	DECLE 16191,37
	;[1862] MUSIC s,F3,s
	SRCFILE "Songs\SHarrierC64.bas",1862
	DECLE 4671,63
	;[1863] MUSIC F2,s,s
	SRCFILE "Songs\SHarrierC64.bas",1863
	DECLE 16134,63
	;[1864] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1864
	DECLE 16191,49
	;[1865] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1865
	DECLE 16191,37
	;[1866] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1866
	DECLE 16191,34
	;[1867] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1867
	DECLE 6463,63
	;[1868] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1868
	DECLE 16191,46
	;[1869] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1869
	DECLE 16191,34
	;[1870] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1870
	DECLE 16191,32
	;[1871] MUSIC F3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1871
	DECLE 5906,63
	;[1872] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1872
	DECLE 16191,44
	;[1873] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1873
	DECLE 16191,32
	;[1874] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1874
	DECLE 16191,34
	;[1875] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1875
	DECLE 6463,63
	;[1876] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1876
	DECLE 16191,46
	;[1877] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1877
	DECLE 16191,34
	;[1878] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1878
	DECLE 16191,30
	;[1879] MUSIC F2,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1879
	DECLE 5638,63
	;[1880] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1880
	DECLE 16191,42
	;[1881] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1881
	DECLE 16191,30
	;[1882] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1882
	DECLE 16191,34
	;[1883] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1883
	DECLE 6463,63
	;[1884] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1884
	DECLE 16191,46
	;[1885] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1885
	DECLE 16191,34
	;[1886] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1886
	DECLE 16191,32
	;[1887] MUSIC F3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1887
	DECLE 5906,63
	;[1888] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1888
	DECLE 16191,44
	;[1889] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1889
	DECLE 16191,32
	;[1890] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1890
	DECLE 16191,34
	;[1891] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1891
	DECLE 6463,63
	;[1892] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1892
	DECLE 16191,46
	;[1893] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1893
	DECLE 16191,34
	;[1894] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1894
	DECLE 16191,39
	;[1895] MUSIC A2#,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1895
	DECLE 5899,63
	;[1896] MUSIC s,s,D6
	SRCFILE "Songs\SHarrierC64.bas",1896
	DECLE 16191,51
	;[1897] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",1897
	DECLE 16191,39
	;[1898] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1898
	DECLE 16191,35
	;[1899] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1899
	DECLE 7743,63
	;[1900] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1900
	DECLE 16191,47
	;[1901] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1901
	DECLE 16191,35
	;[1902] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1902
	DECLE 16191,34
	;[1903] MUSIC A3#,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",1903
	DECLE 7191,63
	;[1904] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1904
	DECLE 16191,46
	;[1905] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1905
	DECLE 16191,34
	;[1906] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1906
	DECLE 16191,35
	;[1907] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1907
	DECLE 7743,63
	;[1908] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1908
	DECLE 16191,47
	;[1909] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1909
	DECLE 16191,35
	;[1910] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1910
	DECLE 16191,30
	;[1911] MUSIC A2#,D4,s
	SRCFILE "Songs\SHarrierC64.bas",1911
	DECLE 6923,63
	;[1912] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1912
	DECLE 16191,42
	;[1913] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1913
	DECLE 16191,30
	;[1914] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1914
	DECLE 16191,35
	;[1915] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1915
	DECLE 7743,63
	;[1916] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1916
	DECLE 16191,47
	;[1917] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1917
	DECLE 16191,35
	;[1918] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1918
	DECLE 16191,34
	;[1919] MUSIC A3#,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",1919
	DECLE 7191,63
	;[1920] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1920
	DECLE 16191,46
	;[1921] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1921
	DECLE 16191,34
	;[1922] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1922
	DECLE 16191,35
	;[1923] MUSIC s,F4,s
	SRCFILE "Songs\SHarrierC64.bas",1923
	DECLE 7743,63
	;[1924] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1924
	DECLE 16191,47
	;[1925] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1925
	DECLE 16191,35
	;[1926] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",1926
	DECLE 16191,63
	;[1927] MUSIC D3#,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1927
	DECLE 4112,63
	;[1928] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",1928
	DECLE 16191,47
	;[1929] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",1929
	DECLE 16191,35
	;[1930] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1930
	DECLE 16191,32
	;[1931] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1931
	DECLE 5951,63
	;[1932] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1932
	DECLE 16191,44
	;[1933] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1933
	DECLE 16191,32
	;[1934] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1934
	DECLE 16191,30
	;[1935] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1935
	DECLE 5648,63
	;[1936] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1936
	DECLE 16191,42
	;[1937] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1937
	DECLE 16191,30
	;[1938] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1938
	DECLE 16191,32
	;[1939] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1939
	DECLE 5951,63
	;[1940] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1940
	DECLE 16191,44
	;[1941] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1941
	DECLE 16191,32
	;[1942] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",1942
	DECLE 16191,28
	;[1943] MUSIC D3#,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1943
	DECLE 5136,63
	;[1944] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",1944
	DECLE 16191,40
	;[1945] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",1945
	DECLE 16191,28
	;[1946] 
	SRCFILE "Songs\SHarrierC64.bas",1946
	;[1947] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1947
	DECLE 16191,32
	;[1948] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1948
	DECLE 5951,63
	;[1949] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1949
	DECLE 16191,44
	;[1950] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1950
	DECLE 16191,32
	;[1951] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1951
	DECLE 16191,30
	;[1952] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",1952
	DECLE 5648,63
	;[1953] MUSIC s,s,F5
	SRCFILE "Songs\SHarrierC64.bas",1953
	DECLE 16191,42
	;[1954] MUSIC s,s,F4
	SRCFILE "Songs\SHarrierC64.bas",1954
	DECLE 16191,30
	;[1955] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1955
	DECLE 16191,32
	;[1956] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",1956
	DECLE 5951,63
	;[1957] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1957
	DECLE 16191,44
	;[1958] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1958
	DECLE 16191,32
	;[1959] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1959
	DECLE 16191,37
	;[1960] MUSIC C3,C3,s
	SRCFILE "Songs\SHarrierC64.bas",1960
	DECLE 3341,63
	;[1961] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1961
	DECLE 16191,49
	;[1962] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1962
	DECLE 16191,37
	;[1963] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1963
	DECLE 16191,34
	;[1964] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1964
	DECLE 5183,63
	;[1965] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1965
	DECLE 16191,46
	;[1966] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1966
	DECLE 4927,34
	;[1967] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1967
	DECLE 16191,32
	;[1968] MUSIC C3,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1968
	DECLE 4109,63
	;[1969] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1969
	DECLE 16191,44
	;[1970] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1970
	DECLE 16191,32
	;[1971] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1971
	DECLE 16191,34
	;[1972] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1972
	DECLE 5183,63
	;[1973] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1973
	DECLE 16191,46
	;[1974] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1974
	DECLE 4927,34
	;[1975] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1975
	DECLE 16191,31
	;[1976] MUSIC C3,C3,s
	SRCFILE "Songs\SHarrierC64.bas",1976
	DECLE 3341,63
	;[1977] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",1977
	DECLE 16191,43
	;[1978] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",1978
	DECLE 16191,31
	;[1979] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1979
	DECLE 16191,34
	;[1980] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1980
	DECLE 5183,63
	;[1981] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1981
	DECLE 16191,46
	;[1982] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1982
	DECLE 4927,34
	;[1983] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1983
	DECLE 16191,32
	;[1984] MUSIC C3,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",1984
	DECLE 4109,63
	;[1985] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",1985
	DECLE 16191,44
	;[1986] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1986
	DECLE 16191,32
	;[1987] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1987
	DECLE 16191,34
	;[1988] MUSIC s,G3,s
	SRCFILE "Songs\SHarrierC64.bas",1988
	DECLE 5183,63
	;[1989] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1989
	DECLE 16191,46
	;[1990] MUSIC s,F3#,A4
	SRCFILE "Songs\SHarrierC64.bas",1990
	DECLE 4927,34
	;[1991] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1991
	DECLE 16191,37
	;[1992] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",1992
	DECLE 3855,63
	;[1993] MUSIC s,s,C6
	SRCFILE "Songs\SHarrierC64.bas",1993
	DECLE 16191,49
	;[1994] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",1994
	DECLE 16191,37
	;[1995] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1995
	DECLE 16191,34
	;[1996] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",1996
	DECLE 6463,63
	;[1997] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",1997
	DECLE 16191,46
	;[1998] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",1998
	DECLE 16191,34
	;[1999] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",1999
	DECLE 16191,32
	;[2000] MUSIC D3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2000
	DECLE 5903,63
	;[2001] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2001
	DECLE 16191,44
	;[2002] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2002
	DECLE 16191,32
	;[2003] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2003
	DECLE 16191,34
	;[2004] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2004
	DECLE 6463,63
	;[2005] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",2005
	DECLE 16191,46
	;[2006] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2006
	DECLE 16191,34
	;[2007] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2007
	DECLE 16191,31
	;[2008] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2008
	DECLE 5647,63
	;[2009] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",2009
	DECLE 16191,43
	;[2010] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2010
	DECLE 16191,31
	;[2011] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2011
	DECLE 16191,34
	;[2012] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2012
	DECLE 6463,63
	;[2013] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",2013
	DECLE 16191,46
	;[2014] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2014
	DECLE 16191,34
	;[2015] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2015
	DECLE 16191,32
	;[2016] MUSIC D3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2016
	DECLE 5903,63
	;[2017] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2017
	DECLE 16191,44
	;[2018] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2018
	DECLE 16191,32
	;[2019] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2019
	DECLE 16191,34
	;[2020] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2020
	DECLE 6463,63
	;[2021] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",2021
	DECLE 16191,46
	;[2022] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2022
	DECLE 16191,34
	;[2023] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2023
	DECLE 16191,35
	;[2024] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",2024
	DECLE 3855,63
	;[2025] MUSIC s,s,A5#
	SRCFILE "Songs\SHarrierC64.bas",2025
	DECLE 16191,47
	;[2026] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2026
	DECLE 16191,35
	;[2027] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2027
	DECLE 16191,32
	;[2028] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2028
	DECLE 5951,63
	;[2029] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2029
	DECLE 16191,44
	;[2030] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2030
	DECLE 16191,32
	;[2031] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2031
	DECLE 16191,31
	;[2032] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2032
	DECLE 5647,63
	;[2033] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",2033
	DECLE 16191,43
	;[2034] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2034
	DECLE 16191,31
	;[2035] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2035
	DECLE 16191,32
	;[2036] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2036
	DECLE 5951,63
	;[2037] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2037
	DECLE 16191,44
	;[2038] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2038
	DECLE 16191,32
	;[2039] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2039
	DECLE 16191,27
	;[2040] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2040
	DECLE 5135,63
	;[2041] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",2041
	DECLE 16191,39
	;[2042] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2042
	DECLE 16191,27
	;[2043] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2043
	DECLE 16191,32
	;[2044] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2044
	DECLE 5951,63
	;[2045] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2045
	DECLE 16191,44
	;[2046] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2046
	DECLE 16191,32
	;[2047] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2047
	DECLE 16191,31
	;[2048] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2048
	DECLE 5647,63
	;[2049] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",2049
	DECLE 16191,43
	;[2050] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2050
	DECLE 16191,31
	;[2051] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2051
	DECLE 16191,32
	;[2052] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2052
	DECLE 5951,63
	;[2053] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2053
	DECLE 16191,44
	;[2054] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2054
	DECLE 16191,32
	;[2055] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2055
	DECLE 16191,34
	;[2056] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",2056
	DECLE 3855,63
	;[2057] MUSIC s,s,A5
	SRCFILE "Songs\SHarrierC64.bas",2057
	DECLE 16191,46
	;[2058] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2058
	DECLE 16191,34
	;[2059] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2059
	DECLE 16191,31
	;[2060] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2060
	DECLE 5695,63
	;[2061] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",2061
	DECLE 16191,43
	;[2062] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2062
	DECLE 16191,31
	;[2063] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2063
	DECLE 16191,29
	;[2064] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2064
	DECLE 5135,63
	;[2065] MUSIC s,s,E5
	SRCFILE "Songs\SHarrierC64.bas",2065
	DECLE 16191,41
	;[2066] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2066
	DECLE 16191,29
	;[2067] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2067
	DECLE 16191,31
	;[2068] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2068
	DECLE 5695,63
	;[2069] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",2069
	DECLE 16191,43
	;[2070] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2070
	DECLE 16191,31
	;[2071] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2071
	DECLE 16191,27
	;[2072] MUSIC D3,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",2072
	DECLE 4879,63
	;[2073] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",2073
	DECLE 16191,39
	;[2074] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2074
	DECLE 16191,27
	;[2075] 
	SRCFILE "Songs\SHarrierC64.bas",2075
	;[2076] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2076
	DECLE 16191,31
	;[2077] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2077
	DECLE 5695,63
	;[2078] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",2078
	DECLE 16191,43
	;[2079] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2079
	DECLE 16191,31
	;[2080] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2080
	DECLE 16191,29
	;[2081] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2081
	DECLE 5135,63
	;[2082] MUSIC s,s,E5
	SRCFILE "Songs\SHarrierC64.bas",2082
	DECLE 16191,41
	;[2083] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2083
	DECLE 16191,29
	;[2084] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2084
	DECLE 16191,31
	;[2085] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2085
	DECLE 5695,63
	;[2086] MUSIC s,s,F5#
	SRCFILE "Songs\SHarrierC64.bas",2086
	DECLE 16191,43
	;[2087] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2087
	DECLE 16191,31
	;[2088] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2088
	DECLE 16191,32
	;[2089] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2089
	DECLE 5128,63
	;[2090] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2090
	DECLE 16191,44
	;[2091] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2091
	DECLE 16191,32
	;[2092] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2092
	DECLE 16191,44
	;[2093] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2093
	DECLE 6975,63
	;[2094] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2094
	DECLE 16191,32
	;[2095] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2095
	DECLE 16191,44
	;[2096] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2096
	DECLE 16191,32
	;[2097] MUSIC G3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2097
	DECLE 5908,63
	;[2098] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2098
	DECLE 16191,44
	;[2099] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2099
	DECLE 16191,32
	;[2100] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2100
	DECLE 16191,44
	;[2101] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2101
	DECLE 6975,63
	;[2102] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2102
	DECLE 16191,32
	;[2103] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2103
	DECLE 16191,44
	;[2104] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2104
	DECLE 16191,32
	;[2105] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2105
	DECLE 5128,63
	;[2106] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2106
	DECLE 16191,44
	;[2107] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2107
	DECLE 16191,32
	;[2108] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2108
	DECLE 16191,44
	;[2109] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2109
	DECLE 6975,63
	;[2110] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2110
	DECLE 16191,32
	;[2111] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2111
	DECLE 16191,44
	;[2112] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2112
	DECLE 16191,32
	;[2113] MUSIC G3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2113
	DECLE 5908,63
	;[2114] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2114
	DECLE 16191,44
	;[2115] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2115
	DECLE 16191,32
	;[2116] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2116
	DECLE 16191,44
	;[2117] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2117
	DECLE 6975,63
	;[2118] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2118
	DECLE 16191,32
	;[2119] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2119
	DECLE 16191,44
	;[2120] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2120
	DECLE 16191,32
	;[2121] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2121
	DECLE 5128,63
	;[2122] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2122
	DECLE 16191,44
	;[2123] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2123
	DECLE 16191,32
	;[2124] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2124
	DECLE 16191,44
	;[2125] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2125
	DECLE 6975,63
	;[2126] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2126
	DECLE 16191,32
	;[2127] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2127
	DECLE 16191,44
	;[2128] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2128
	DECLE 16191,32
	;[2129] MUSIC G3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2129
	DECLE 5908,63
	;[2130] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2130
	DECLE 16191,44
	;[2131] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2131
	DECLE 16191,32
	;[2132] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2132
	DECLE 16191,44
	;[2133] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2133
	DECLE 6975,63
	;[2134] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2134
	DECLE 16191,32
	;[2135] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2135
	DECLE 16191,44
	;[2136] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2136
	DECLE 16191,32
	;[2137] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2137
	DECLE 5128,63
	;[2138] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2138
	DECLE 16191,44
	;[2139] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2139
	DECLE 16191,32
	;[2140] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2140
	DECLE 16191,44
	;[2141] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2141
	DECLE 6975,63
	;[2142] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2142
	DECLE 16191,32
	;[2143] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2143
	DECLE 16191,44
	;[2144] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2144
	DECLE 16191,32
	;[2145] MUSIC G3,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2145
	DECLE 5908,63
	;[2146] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2146
	DECLE 16191,44
	;[2147] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2147
	DECLE 16191,32
	;[2148] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2148
	DECLE 16191,44
	;[2149] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2149
	DECLE 6975,63
	;[2150] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2150
	DECLE 16191,32
	;[2151] MUSIC s,s,G5
	SRCFILE "Songs\SHarrierC64.bas",2151
	DECLE 16191,44
	;[2152] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2152
	DECLE 16191,63
	;[2153] MUSIC G2,G3,D5
	SRCFILE "Songs\SHarrierC64.bas",2153
	DECLE 5128,39
	;[2154] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2154
	DECLE 16191,63
	;[2155] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2155
	DECLE 16191,63
	;[2156] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2156
	DECLE 16191,35
	;[2157] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2157
	DECLE 6975,63
	;[2158] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2158
	DECLE 16191,63
	;[2159] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2159
	DECLE 16191,63
	;[2160] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2160
	DECLE 16191,34
	;[2161] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2161
	DECLE 6420,63
	;[2162] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2162
	DECLE 16191,63
	;[2163] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2163
	DECLE 16191,63
	;[2164] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2164
	DECLE 16191,35
	;[2165] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2165
	DECLE 6975,63
	;[2166] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2166
	DECLE 16191,63
	;[2167] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2167
	DECLE 16191,63
	;[2168] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2168
	DECLE 16191,32
	;[2169] MUSIC G2,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2169
	DECLE 5896,63
	;[2170] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2170
	DECLE 16191,63
	;[2171] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2171
	DECLE 16191,63
	;[2172] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2172
	DECLE 16191,35
	;[2173] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2173
	DECLE 6975,63
	;[2174] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2174
	DECLE 16191,63
	;[2175] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2175
	DECLE 16191,63
	;[2176] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2176
	DECLE 16191,34
	;[2177] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2177
	DECLE 6420,63
	;[2178] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2178
	DECLE 16191,63
	;[2179] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2179
	DECLE 16191,63
	;[2180] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2180
	DECLE 16191,35
	;[2181] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2181
	DECLE 6975,63
	;[2182] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2182
	DECLE 16191,63
	;[2183] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2183
	DECLE 16191,63
	;[2184] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",2184
	DECLE 16191,39
	;[2185] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2185
	DECLE 5128,63
	;[2186] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2186
	DECLE 16191,63
	;[2187] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2187
	DECLE 16191,63
	;[2188] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2188
	DECLE 16191,35
	;[2189] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2189
	DECLE 6975,63
	;[2190] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2190
	DECLE 16191,63
	;[2191] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2191
	DECLE 16191,63
	;[2192] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2192
	DECLE 16191,34
	;[2193] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2193
	DECLE 6420,63
	;[2194] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2194
	DECLE 16191,63
	;[2195] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2195
	DECLE 16191,63
	;[2196] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2196
	DECLE 16191,35
	;[2197] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2197
	DECLE 6975,63
	;[2198] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2198
	DECLE 16191,63
	;[2199] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2199
	DECLE 16191,63
	;[2200] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2200
	DECLE 16191,32
	;[2201] MUSIC G2,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2201
	DECLE 5896,63
	;[2202] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2202
	DECLE 16191,63
	;[2203] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2203
	DECLE 16191,63
	;[2204] 
	SRCFILE "Songs\SHarrierC64.bas",2204
	;[2205] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2205
	DECLE 16191,35
	;[2206] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2206
	DECLE 6975,63
	;[2207] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2207
	DECLE 16191,63
	;[2208] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2208
	DECLE 16191,63
	;[2209] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2209
	DECLE 16191,34
	;[2210] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2210
	DECLE 6420,63
	;[2211] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2211
	DECLE 16191,63
	;[2212] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2212
	DECLE 16191,63
	;[2213] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2213
	DECLE 16191,35
	;[2214] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2214
	DECLE 6975,63
	;[2215] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2215
	DECLE 16191,63
	;[2216] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2216
	DECLE 16191,63
	;[2217] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",2217
	DECLE 16191,40
	;[2218] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2218
	DECLE 5128,63
	;[2219] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2219
	DECLE 16191,63
	;[2220] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2220
	DECLE 16191,63
	;[2221] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2221
	DECLE 16191,37
	;[2222] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2222
	DECLE 7231,63
	;[2223] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2223
	DECLE 16191,63
	;[2224] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2224
	DECLE 16191,63
	;[2225] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",2225
	DECLE 16191,36
	;[2226] MUSIC G3,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2226
	DECLE 6932,63
	;[2227] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2227
	DECLE 16191,63
	;[2228] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2228
	DECLE 16191,63
	;[2229] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2229
	DECLE 16191,37
	;[2230] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2230
	DECLE 7231,63
	;[2231] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2231
	DECLE 16191,63
	;[2232] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2232
	DECLE 16191,63
	;[2233] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2233
	DECLE 16191,32
	;[2234] MUSIC G2,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2234
	DECLE 6408,63
	;[2235] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2235
	DECLE 16191,63
	;[2236] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2236
	DECLE 16191,63
	;[2237] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2237
	DECLE 16191,37
	;[2238] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2238
	DECLE 7231,63
	;[2239] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2239
	DECLE 16191,63
	;[2240] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2240
	DECLE 16191,63
	;[2241] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",2241
	DECLE 16191,36
	;[2242] MUSIC G3,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2242
	DECLE 6932,63
	;[2243] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2243
	DECLE 16191,63
	;[2244] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2244
	DECLE 16191,63
	;[2245] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2245
	DECLE 16191,37
	;[2246] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2246
	DECLE 7231,63
	;[2247] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2247
	DECLE 16191,63
	;[2248] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2248
	DECLE 16191,63
	;[2249] MUSIC s,s,D5#
	SRCFILE "Songs\SHarrierC64.bas",2249
	DECLE 16191,40
	;[2250] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2250
	DECLE 5128,63
	;[2251] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2251
	DECLE 16191,63
	;[2252] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2252
	DECLE 16191,63
	;[2253] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2253
	DECLE 16191,37
	;[2254] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2254
	DECLE 7231,63
	;[2255] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2255
	DECLE 16191,63
	;[2256] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2256
	DECLE 16191,63
	;[2257] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",2257
	DECLE 16191,36
	;[2258] MUSIC G3,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2258
	DECLE 6932,63
	;[2259] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2259
	DECLE 16191,63
	;[2260] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2260
	DECLE 16191,63
	;[2261] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2261
	DECLE 16191,37
	;[2262] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2262
	DECLE 7231,63
	;[2263] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2263
	DECLE 16191,63
	;[2264] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2264
	DECLE 16191,63
	;[2265] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2265
	DECLE 16191,32
	;[2266] MUSIC G2,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2266
	DECLE 6408,63
	;[2267] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2267
	DECLE 16191,63
	;[2268] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2268
	DECLE 16191,63
	;[2269] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2269
	DECLE 16191,37
	;[2270] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2270
	DECLE 7231,63
	;[2271] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2271
	DECLE 16191,63
	;[2272] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2272
	DECLE 16191,63
	;[2273] MUSIC s,s,B4
	SRCFILE "Songs\SHarrierC64.bas",2273
	DECLE 16191,36
	;[2274] MUSIC G3,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2274
	DECLE 6932,63
	;[2275] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2275
	DECLE 16191,63
	;[2276] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2276
	DECLE 16191,63
	;[2277] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2277
	DECLE 16191,37
	;[2278] MUSIC s,D4#,s
	SRCFILE "Songs\SHarrierC64.bas",2278
	DECLE 7231,63
	;[2279] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2279
	DECLE 16191,63
	;[2280] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2280
	DECLE 16191,63
	;[2281] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",2281
	DECLE 16191,39
	;[2282] MUSIC F2#,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",2282
	DECLE 4871,63
	;[2283] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2283
	DECLE 16191,63
	;[2284] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2284
	DECLE 16191,63
	;[2285] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2285
	DECLE 16191,34
	;[2286] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2286
	DECLE 6975,63
	;[2287] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2287
	DECLE 16191,63
	;[2288] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2288
	DECLE 16191,63
	;[2289] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2289
	DECLE 16191,32
	;[2290] MUSIC F3#,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2290
	DECLE 6419,63
	;[2291] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2291
	DECLE 16191,63
	;[2292] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2292
	DECLE 16191,63
	;[2293] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2293
	DECLE 16191,34
	;[2294] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2294
	DECLE 6975,63
	;[2295] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2295
	DECLE 16191,63
	;[2296] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2296
	DECLE 16191,63
	;[2297] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2297
	DECLE 16191,31
	;[2298] MUSIC F2#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2298
	DECLE 5639,63
	;[2299] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2299
	DECLE 16191,63
	;[2300] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2300
	DECLE 16191,63
	;[2301] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2301
	DECLE 16191,34
	;[2302] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2302
	DECLE 6975,63
	;[2303] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2303
	DECLE 16191,63
	;[2304] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2304
	DECLE 16191,63
	;[2305] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2305
	DECLE 16191,32
	;[2306] MUSIC F3#,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2306
	DECLE 6419,63
	;[2307] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2307
	DECLE 16191,63
	;[2308] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2308
	DECLE 16191,63
	;[2309] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2309
	DECLE 16191,34
	;[2310] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2310
	DECLE 6975,63
	;[2311] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2311
	DECLE 16191,63
	;[2312] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2312
	DECLE 16191,63
	;[2313] MUSIC s,s,D5
	SRCFILE "Songs\SHarrierC64.bas",2313
	DECLE 16191,39
	;[2314] MUSIC F2#,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",2314
	DECLE 4871,63
	;[2315] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2315
	DECLE 16191,63
	;[2316] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2316
	DECLE 16191,63
	;[2317] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2317
	DECLE 16191,34
	;[2318] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2318
	DECLE 6975,63
	;[2319] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2319
	DECLE 16191,63
	;[2320] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2320
	DECLE 16191,63
	;[2321] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2321
	DECLE 16191,32
	;[2322] MUSIC F3#,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2322
	DECLE 6419,63
	;[2323] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2323
	DECLE 16191,63
	;[2324] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2324
	DECLE 16191,63
	;[2325] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2325
	DECLE 16191,34
	;[2326] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2326
	DECLE 6975,63
	;[2327] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2327
	DECLE 16191,63
	;[2328] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2328
	DECLE 16191,63
	;[2329] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2329
	DECLE 16191,31
	;[2330] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2330
	DECLE 5647,63
	;[2331] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2331
	DECLE 16191,63
	;[2332] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2332
	DECLE 16191,63
	;[2333] 
	SRCFILE "Songs\SHarrierC64.bas",2333
	;[2334] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2334
	DECLE 16191,34
	;[2335] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2335
	DECLE 6975,63
	;[2336] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2336
	DECLE 16191,63
	;[2337] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2337
	DECLE 16191,63
	;[2338] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2338
	DECLE 16191,32
	;[2339] MUSIC D3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2339
	DECLE 6415,63
	;[2340] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2340
	DECLE 16191,63
	;[2341] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2341
	DECLE 16191,63
	;[2342] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2342
	DECLE 16191,34
	;[2343] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2343
	DECLE 6975,63
	;[2344] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2344
	DECLE 16191,63
	;[2345] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2345
	DECLE 16191,63
	;[2346] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2346
	DECLE 16191,35
	;[2347] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2347
	DECLE 5128,63
	;[2348] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2348
	DECLE 16191,63
	;[2349] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2349
	DECLE 16191,63
	;[2350] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2350
	DECLE 16191,32
	;[2351] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2351
	DECLE 6975,63
	;[2352] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2352
	DECLE 16191,63
	;[2353] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2353
	DECLE 16191,63
	;[2354] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2354
	DECLE 16191,31
	;[2355] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2355
	DECLE 6420,63
	;[2356] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2356
	DECLE 16191,63
	;[2357] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2357
	DECLE 16191,63
	;[2358] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2358
	DECLE 16191,32
	;[2359] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2359
	DECLE 6975,63
	;[2360] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2360
	DECLE 16191,63
	;[2361] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2361
	DECLE 16191,63
	;[2362] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2362
	DECLE 16191,27
	;[2363] MUSIC G2,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2363
	DECLE 5896,63
	;[2364] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2364
	DECLE 16191,63
	;[2365] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2365
	DECLE 16191,63
	;[2366] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2366
	DECLE 16191,32
	;[2367] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2367
	DECLE 6975,63
	;[2368] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2368
	DECLE 16191,63
	;[2369] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2369
	DECLE 16191,63
	;[2370] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2370
	DECLE 16191,31
	;[2371] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2371
	DECLE 6420,63
	;[2372] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2372
	DECLE 16191,63
	;[2373] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2373
	DECLE 16191,63
	;[2374] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2374
	DECLE 16191,32
	;[2375] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2375
	DECLE 6975,63
	;[2376] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2376
	DECLE 16191,63
	;[2377] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2377
	DECLE 16191,63
	;[2378] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2378
	DECLE 16191,35
	;[2379] MUSIC G2,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2379
	DECLE 5128,63
	;[2380] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2380
	DECLE 16191,63
	;[2381] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2381
	DECLE 16191,63
	;[2382] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2382
	DECLE 16191,32
	;[2383] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2383
	DECLE 6975,63
	;[2384] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2384
	DECLE 16191,63
	;[2385] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2385
	DECLE 16191,63
	;[2386] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2386
	DECLE 16191,31
	;[2387] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2387
	DECLE 6420,63
	;[2388] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2388
	DECLE 16191,63
	;[2389] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2389
	DECLE 16191,63
	;[2390] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2390
	DECLE 16191,32
	;[2391] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2391
	DECLE 6975,63
	;[2392] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2392
	DECLE 16191,63
	;[2393] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2393
	DECLE 16191,63
	;[2394] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2394
	DECLE 16191,27
	;[2395] MUSIC G2,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2395
	DECLE 5896,63
	;[2396] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2396
	DECLE 16191,63
	;[2397] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2397
	DECLE 16191,63
	;[2398] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2398
	DECLE 16191,32
	;[2399] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2399
	DECLE 6975,63
	;[2400] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2400
	DECLE 16191,63
	;[2401] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2401
	DECLE 16191,63
	;[2402] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2402
	DECLE 16191,31
	;[2403] MUSIC G3,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2403
	DECLE 6420,63
	;[2404] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2404
	DECLE 16191,63
	;[2405] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2405
	DECLE 16191,63
	;[2406] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2406
	DECLE 16191,32
	;[2407] MUSIC s,D4,s
	SRCFILE "Songs\SHarrierC64.bas",2407
	DECLE 6975,63
	;[2408] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2408
	DECLE 16191,63
	;[2409] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2409
	DECLE 16191,63
	;[2410] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2410
	DECLE 16191,37
	;[2411] MUSIC D3#,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",2411
	DECLE 4112,63
	;[2412] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2412
	DECLE 16191,63
	;[2413] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2413
	DECLE 16191,63
	;[2414] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2414
	DECLE 16191,32
	;[2415] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2415
	DECLE 6463,63
	;[2416] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2416
	DECLE 16191,63
	;[2417] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2417
	DECLE 16191,63
	;[2418] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2418
	DECLE 16191,31
	;[2419] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2419
	DECLE 5648,63
	;[2420] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2420
	DECLE 16191,63
	;[2421] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2421
	DECLE 16191,63
	;[2422] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2422
	DECLE 16191,32
	;[2423] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2423
	DECLE 6463,63
	;[2424] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2424
	DECLE 16191,63
	;[2425] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2425
	DECLE 16191,63
	;[2426] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",2426
	DECLE 16191,28
	;[2427] MUSIC D3#,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2427
	DECLE 5136,63
	;[2428] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2428
	DECLE 16191,63
	;[2429] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2429
	DECLE 16191,63
	;[2430] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2430
	DECLE 16191,32
	;[2431] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2431
	DECLE 6463,63
	;[2432] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2432
	DECLE 16191,63
	;[2433] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2433
	DECLE 16191,63
	;[2434] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2434
	DECLE 16191,31
	;[2435] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2435
	DECLE 5648,63
	;[2436] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2436
	DECLE 16191,63
	;[2437] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2437
	DECLE 16191,63
	;[2438] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2438
	DECLE 16191,32
	;[2439] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2439
	DECLE 6463,63
	;[2440] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2440
	DECLE 16191,63
	;[2441] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2441
	DECLE 16191,63
	;[2442] MUSIC s,s,C5
	SRCFILE "Songs\SHarrierC64.bas",2442
	DECLE 16191,37
	;[2443] MUSIC D3#,D3#,s
	SRCFILE "Songs\SHarrierC64.bas",2443
	DECLE 4112,63
	;[2444] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2444
	DECLE 16191,63
	;[2445] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2445
	DECLE 16191,63
	;[2446] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2446
	DECLE 16191,32
	;[2447] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2447
	DECLE 6463,63
	;[2448] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2448
	DECLE 16191,63
	;[2449] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2449
	DECLE 16191,63
	;[2450] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2450
	DECLE 16191,31
	;[2451] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2451
	DECLE 5648,63
	;[2452] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2452
	DECLE 16191,63
	;[2453] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2453
	DECLE 16191,63
	;[2454] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2454
	DECLE 16191,32
	;[2455] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2455
	DECLE 6463,63
	;[2456] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2456
	DECLE 16191,63
	;[2457] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2457
	DECLE 16191,63
	;[2458] MUSIC s,s,D4#
	SRCFILE "Songs\SHarrierC64.bas",2458
	DECLE 16191,28
	;[2459] MUSIC D3#,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2459
	DECLE 5136,63
	;[2460] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2460
	DECLE 16191,63
	;[2461] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2461
	DECLE 16191,63
	;[2462] 
	SRCFILE "Songs\SHarrierC64.bas",2462
	;[2463] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2463
	DECLE 16191,32
	;[2464] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2464
	DECLE 6463,63
	;[2465] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2465
	DECLE 16191,63
	;[2466] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2466
	DECLE 16191,63
	;[2467] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2467
	DECLE 16191,31
	;[2468] MUSIC D3#,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2468
	DECLE 5648,63
	;[2469] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2469
	DECLE 16191,63
	;[2470] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2470
	DECLE 16191,63
	;[2471] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2471
	DECLE 16191,32
	;[2472] MUSIC s,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2472
	DECLE 6463,63
	;[2473] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2473
	DECLE 16191,63
	;[2474] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2474
	DECLE 16191,63
	;[2475] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2475
	DECLE 16191,35
	;[2476] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",2476
	DECLE 3855,63
	;[2477] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2477
	DECLE 16191,63
	;[2478] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2478
	DECLE 16191,63
	;[2479] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2479
	DECLE 16191,32
	;[2480] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2480
	DECLE 5951,63
	;[2481] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2481
	DECLE 16191,63
	;[2482] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2482
	DECLE 16191,63
	;[2483] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2483
	DECLE 16191,31
	;[2484] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2484
	DECLE 5647,63
	;[2485] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2485
	DECLE 16191,63
	;[2486] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2486
	DECLE 16191,63
	;[2487] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2487
	DECLE 16191,32
	;[2488] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2488
	DECLE 5951,63
	;[2489] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2489
	DECLE 16191,63
	;[2490] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2490
	DECLE 16191,63
	;[2491] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2491
	DECLE 16191,27
	;[2492] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2492
	DECLE 5135,63
	;[2493] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2493
	DECLE 16191,63
	;[2494] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2494
	DECLE 16191,63
	;[2495] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2495
	DECLE 16191,32
	;[2496] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2496
	DECLE 5951,63
	;[2497] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2497
	DECLE 16191,63
	;[2498] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2498
	DECLE 16191,63
	;[2499] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2499
	DECLE 16191,31
	;[2500] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2500
	DECLE 5647,63
	;[2501] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2501
	DECLE 16191,63
	;[2502] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2502
	DECLE 16191,63
	;[2503] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2503
	DECLE 16191,32
	;[2504] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2504
	DECLE 5951,63
	;[2505] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2505
	DECLE 16191,63
	;[2506] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2506
	DECLE 16191,63
	;[2507] MUSIC s,s,A4#
	SRCFILE "Songs\SHarrierC64.bas",2507
	DECLE 16191,35
	;[2508] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",2508
	DECLE 3855,63
	;[2509] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2509
	DECLE 16191,63
	;[2510] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2510
	DECLE 16191,63
	;[2511] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2511
	DECLE 16191,32
	;[2512] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2512
	DECLE 5951,63
	;[2513] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2513
	DECLE 16191,63
	;[2514] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2514
	DECLE 16191,63
	;[2515] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2515
	DECLE 16191,31
	;[2516] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2516
	DECLE 5647,63
	;[2517] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2517
	DECLE 16191,63
	;[2518] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2518
	DECLE 16191,63
	;[2519] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2519
	DECLE 16191,32
	;[2520] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2520
	DECLE 5951,63
	;[2521] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2521
	DECLE 16191,63
	;[2522] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2522
	DECLE 16191,63
	;[2523] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2523
	DECLE 16191,27
	;[2524] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2524
	DECLE 5135,63
	;[2525] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2525
	DECLE 16191,63
	;[2526] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2526
	DECLE 16191,63
	;[2527] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2527
	DECLE 16191,32
	;[2528] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2528
	DECLE 5951,63
	;[2529] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2529
	DECLE 16191,63
	;[2530] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2530
	DECLE 16191,63
	;[2531] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2531
	DECLE 16191,31
	;[2532] MUSIC D3,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2532
	DECLE 5647,63
	;[2533] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2533
	DECLE 16191,63
	;[2534] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2534
	DECLE 16191,63
	;[2535] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2535
	DECLE 16191,32
	;[2536] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2536
	DECLE 5951,63
	;[2537] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2537
	DECLE 16191,63
	;[2538] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2538
	DECLE 16191,63
	;[2539] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2539
	DECLE 16191,34
	;[2540] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",2540
	DECLE 3855,63
	;[2541] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2541
	DECLE 16191,63
	;[2542] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2542
	DECLE 16191,63
	;[2543] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2543
	DECLE 16191,31
	;[2544] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2544
	DECLE 5695,63
	;[2545] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2545
	DECLE 16191,63
	;[2546] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2546
	DECLE 16191,63
	;[2547] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2547
	DECLE 16191,29
	;[2548] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2548
	DECLE 5135,63
	;[2549] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2549
	DECLE 16191,63
	;[2550] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2550
	DECLE 16191,63
	;[2551] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2551
	DECLE 16191,31
	;[2552] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2552
	DECLE 5695,63
	;[2553] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2553
	DECLE 16191,63
	;[2554] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2554
	DECLE 16191,63
	;[2555] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2555
	DECLE 16191,27
	;[2556] MUSIC D3,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",2556
	DECLE 4879,63
	;[2557] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2557
	DECLE 16191,63
	;[2558] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2558
	DECLE 16191,63
	;[2559] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2559
	DECLE 16191,31
	;[2560] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2560
	DECLE 5695,63
	;[2561] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2561
	DECLE 16191,63
	;[2562] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2562
	DECLE 16191,63
	;[2563] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2563
	DECLE 16191,29
	;[2564] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2564
	DECLE 5135,63
	;[2565] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2565
	DECLE 16191,63
	;[2566] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2566
	DECLE 16191,63
	;[2567] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2567
	DECLE 16191,31
	;[2568] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2568
	DECLE 5695,63
	;[2569] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2569
	DECLE 16191,63
	;[2570] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2570
	DECLE 16191,63
	;[2571] MUSIC s,s,A4
	SRCFILE "Songs\SHarrierC64.bas",2571
	DECLE 16191,34
	;[2572] MUSIC D3,D3,s
	SRCFILE "Songs\SHarrierC64.bas",2572
	DECLE 3855,63
	;[2573] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2573
	DECLE 16191,63
	;[2574] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2574
	DECLE 16191,63
	;[2575] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2575
	DECLE 16191,31
	;[2576] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2576
	DECLE 5695,63
	;[2577] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2577
	DECLE 16191,63
	;[2578] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2578
	DECLE 16191,63
	;[2579] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2579
	DECLE 16191,29
	;[2580] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2580
	DECLE 5135,63
	;[2581] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2581
	DECLE 16191,63
	;[2582] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2582
	DECLE 16191,63
	;[2583] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2583
	DECLE 16191,31
	;[2584] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2584
	DECLE 5695,63
	;[2585] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2585
	DECLE 16191,63
	;[2586] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2586
	DECLE 16191,63
	;[2587] MUSIC s,s,D4
	SRCFILE "Songs\SHarrierC64.bas",2587
	DECLE 16191,27
	;[2588] MUSIC D3,F3#,s
	SRCFILE "Songs\SHarrierC64.bas",2588
	DECLE 4879,63
	;[2589] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2589
	DECLE 16191,63
	;[2590] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2590
	DECLE 16191,63
	;[2591] 
	SRCFILE "Songs\SHarrierC64.bas",2591
	;[2592] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2592
	DECLE 16191,31
	;[2593] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2593
	DECLE 5695,63
	;[2594] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2594
	DECLE 16191,63
	;[2595] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2595
	DECLE 16191,63
	;[2596] MUSIC s,s,E4
	SRCFILE "Songs\SHarrierC64.bas",2596
	DECLE 16191,29
	;[2597] MUSIC D3,G3,s
	SRCFILE "Songs\SHarrierC64.bas",2597
	DECLE 5135,63
	;[2598] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2598
	DECLE 16191,63
	;[2599] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2599
	DECLE 16191,63
	;[2600] MUSIC s,s,F4#
	SRCFILE "Songs\SHarrierC64.bas",2600
	DECLE 16191,31
	;[2601] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2601
	DECLE 5695,63
	;[2602] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2602
	DECLE 16191,63
	;[2603] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2603
	DECLE 16191,63
	;[2604] MUSIC s,s,G4
	SRCFILE "Songs\SHarrierC64.bas",2604
	DECLE 16191,32
	;[2605] MUSIC G2,C4,s
	SRCFILE "Songs\SHarrierC64.bas",2605
	DECLE 6408,63
	;[2606] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2606
	DECLE 16191,63
	;[2607] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2607
	DECLE 16191,63
	;[2608] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2608
	DECLE 16191,63
	;[2609] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2609
	DECLE 16191,63
	;[2610] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2610
	DECLE 16191,63
	;[2611] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2611
	DECLE 16191,63
	;[2612] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2612
	DECLE 16191,63
	;[2613] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2613
	DECLE 16191,63
	;[2614] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2614
	DECLE 16191,63
	;[2615] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2615
	DECLE 16191,63
	;[2616] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2616
	DECLE 16191,63
	;[2617] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2617
	DECLE 16191,63
	;[2618] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2618
	DECLE 16191,63
	;[2619] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2619
	DECLE 16191,63
	;[2620] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2620
	DECLE 16191,63
	;[2621] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2621
	DECLE 5951,63
	;[2622] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2622
	DECLE 16191,63
	;[2623] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2623
	DECLE 16191,63
	;[2624] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2624
	DECLE 16191,63
	;[2625] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2625
	DECLE 16191,63
	;[2626] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2626
	DECLE 16191,63
	;[2627] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2627
	DECLE 16191,63
	;[2628] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2628
	DECLE 16191,63
	;[2629] MUSIC s,A3,s
	SRCFILE "Songs\SHarrierC64.bas",2629
	DECLE 5695,63
	;[2630] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2630
	DECLE 16191,63
	;[2631] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2631
	DECLE 16191,63
	;[2632] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2632
	DECLE 16191,63
	;[2633] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2633
	DECLE 16191,63
	;[2634] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2634
	DECLE 16191,63
	;[2635] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2635
	DECLE 16191,63
	;[2636] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2636
	DECLE 16191,63
	;[2637] MUSIC s,A3#,s
	SRCFILE "Songs\SHarrierC64.bas",2637
	DECLE 5951,63
	;[2638] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2638
	DECLE 16191,63
	;[2639] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2639
	DECLE 16191,63
	;[2640] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2640
	DECLE 16191,63
	;[2641] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2641
	DECLE 16191,63
	;[2642] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2642
	DECLE 16191,63
	;[2643] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2643
	DECLE 16191,63
	;[2644] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2644
	DECLE 16191,63
	;[2645] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2645
	DECLE 16191,63
	;[2646] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2646
	DECLE 16191,63
	;[2647] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2647
	DECLE 16191,63
	;[2648] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2648
	DECLE 16191,63
	;[2649] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2649
	DECLE 16191,63
	;[2650] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2650
	DECLE 16191,63
	;[2651] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2651
	DECLE 16191,63
	;[2652] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2652
	DECLE 16191,63
	;[2653] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2653
	DECLE 16191,63
	;[2654] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2654
	DECLE 16191,63
	;[2655] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2655
	DECLE 16191,63
	;[2656] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2656
	DECLE 16191,63
	;[2657] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2657
	DECLE 16191,63
	;[2658] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2658
	DECLE 16191,63
	;[2659] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2659
	DECLE 16191,63
	;[2660] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2660
	DECLE 16191,63
	;[2661] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2661
	DECLE 16191,63
	;[2662] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2662
	DECLE 16191,63
	;[2663] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2663
	DECLE 16191,63
	;[2664] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2664
	DECLE 16191,63
	;[2665] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2665
	DECLE 16191,63
	;[2666] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2666
	DECLE 16191,63
	;[2667] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2667
	DECLE 16191,63
	;[2668] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2668
	DECLE 16191,63
	;[2669] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2669
	DECLE 16191,63
	;[2670] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2670
	DECLE 16191,63
	;[2671] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2671
	DECLE 16191,63
	;[2672] MUSIC s,s,s
	SRCFILE "Songs\SHarrierC64.bas",2672
	DECLE 16191,63
	;[2673] MUSIC STOP
	SRCFILE "Songs\SHarrierC64.bas",2673
	DECLE 254,0
	;ENDFILE
	;FILE IntyMusic.bas
	;[70] 
	SRCFILE "IntyMusic.bas",70
	;[71] '--- song name, printed vertically --- Must be 12 characters or less! -----
	SRCFILE "IntyMusic.bas",71
	;[72] MyMusicName:
	SRCFILE "IntyMusic.bas",72
	; MYMUSICNAME
Q39:	;[73] DATA "SHarrier C64"
	SRCFILE "IntyMusic.bas",73
	DECLE 51
	DECLE 40
	DECLE 65
	DECLE 82
	DECLE 82
	DECLE 73
	DECLE 69
	DECLE 82
	DECLE 0
	DECLE 35
	DECLE 22
	DECLE 20
	;[74] REM "123456789012"
	SRCFILE "IntyMusic.bas",74
	;[75] '--- To disable this text, change this above: CONST INTYMUSIC_SONG_TITLE = 0 
	SRCFILE "IntyMusic.bas",75
	;[76] 
	SRCFILE "IntyMusic.bas",76
	;[77] '======= Options #2 End =======
	SRCFILE "IntyMusic.bas",77
	;[78] ''NOTE: If Music speed is 1, IntyMusic will not scroll, change the following in IntyMusicPlayer.bas:
	SRCFILE "IntyMusic.bas",78
	;[79] ''IF #iMusicTime(1)=#iMusicTime(0) THEN	 ---change to----> IF #iMusicTime(1)=1 THEN	
	SRCFILE "IntyMusic.bas",79
	;[80] 
	SRCFILE "IntyMusic.bas",80
	;[81] DATA 0,0,0,0,0,0,0,0,0,0,0,0
	SRCFILE "IntyMusic.bas",81
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;ENDFILE
	SRCFILE "",0
intybasic_scroll:	equ 1	; Forces to include scroll library
intybasic_keypad:	equ 1	; Forces to include keypad library
intybasic_music:	equ 1	; Forces to include music library
        ;
        ; Epilogue for IntyBASIC programs
        ; by Oscar Toledo G.  http://nanochess.org/
        ;
        ; Revision: Jan/30/2014. Moved GRAM code below MOB updates.
        ;                        Added comments.
        ; Revision: Feb/26/2014. Optimized access to collision registers
        ;                        per DZ-Jay suggestion. Added scrolling
        ;                        routines with optimization per intvnut
        ;                        suggestion. Added border/mask support.
        ; Revision: Apr/02/2014. Added support to set MODE (color stack
        ;                        or foreground/background), added support
        ;                        for SCREEN statement.
        ; Revision: Aug/19/2014. Solved bug in bottom scroll, moved an
        ;                        extra unneeded line.
        ; Revision: Aug/26/2014. Integrated music player and NTSC/PAL
        ;                        detection.
        ; Revision: Oct/24/2014. Adjust in some comments.
        ; Revision: Nov/13/2014. Integrated Joseph Zbiciak's routines
        ;                        for printing numbers.
        ; Revision: Nov/17/2014. Redesigned MODE support to use a single
        ;                        variable.
        ; Revision: Nov/21/2014. Added Intellivoice support routines made
        ;                        by Joseph Zbiciak.
	; Revision: Dec/11/2014. Optimized keypad decode routines.
	; Revision: Jan/25/2015. Added marker for insertion of ON FRAME GOSUB
	; Revision: Feb/17/2015. Allows to deactivate music player (PLAY NONE)
	; Revision: Apr/21/2015. Accelerates common case of keypad not pressed.
	;                        Added ECS ROM disable code.
	; Revision: Apr/22/2015. Added Joseph Zbiciak accelerated multiplication
	;                        routines.
	; Revision: Jun/04/2015. Optimized play_music (per GroovyBee suggestion)
	; Revision: Jul/25/2015. Added infinite loop at start to avoid crashing
	;                        with empty programs. Solved bug where _color
	;                        didn't started with white.
	; Revision: Aug/20/2015. Moved ECS mapper disable code so nothing gets
	;                        after it (GroovyBee 42K sample code)
	; Revision: Aug/21/2015. Added Joseph Zbiciak routines for JLP Flash
	;                        handling.
	; Revision: Aug/31/2015. Added CPYBLK2 for SCREEN fifth argument.
	; Revision: Sep/01/2015. Defined labels Q1 and Q2 as alias.
	; Revision: Jan/22/2016. Music player allows not to use noise channel
	;                        for drums. Allows setting music volume.
	; Revision: Jan/23/2016. Added jump inside of music (for MUSIC JUMP)

	;
	; Avoids empty programs to crash
	; 
stuck:	B stuck

	;
	; Copy screen helper for SCREEN wide statement
	;

CPYBLK2:	PROC
	MOVR R0,R3		; Offset
	MOVR R5,R2
	PULR R0
	PULR R1
	PULR R5
	PULR R4
	PSHR R2
	SUBR R1,R3

@@1:    PSHR R3
	MOVR R1,R3              ; Init line copy
@@2:    MVI@ R4,R2              ; Copy line
        MVO@ R2,R5
        DECR R3
        BNE @@2
        PULR R3                 ; Add offset to start in next line
        ADDR R3,R4
	SUBR R1,R5
        ADDI #20,R5
        DECR R0                 ; Count lines
        BNE @@1

	RETURN
	ENDP

        ;
        ; Copy screen helper for SCREEN statement
        ;
CPYBLK: PROC
        BEGIN
        MOVR R3,R4
        MOVR R2,R5

@@1:    MOVR R1,R3              ; Init line copy
@@2:    MVI@ R4,R2              ; Copy line
        MVO@ R2,R5
        DECR R3
        BNE @@2
        MVII #20,R3             ; Add offset to start in next line
        SUBR R1,R3
        ADDR R3,R4
        ADDR R3,R5
        DECR R0                 ; Count lines
        BNE @@1
	RETURN
        ENDP

        ;
        ; Wait for interruption
        ;
_wait:  PROC

    IF DEFINED intybasic_keypad
        MVI $01FF,R0
        COMR R0
        ANDI #$FF,R0
        CMP _cnt1_p0,R0
        BNE @@2
        CMP _cnt1_p1,R0
        BNE @@2
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@4
        MVII #_keypad_table,R4
    REPEAT 6
        CMP@ R4,R0
        BEQ @@4
	CMP@ R4,R0
        BEQ @@4
    ENDR
	INCR R4
@@4:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt1_key

@@2:    MVI _cnt1_p1,R1
        MVO R1,_cnt1_p0
        MVO R0,_cnt1_p1

        MVI $01FE,R0
        COMR R0
        ANDI #$FF,R0
        CMP _cnt2_p0,R0
        BNE @@5
        CMP _cnt2_p1,R0
        BNE @@5
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@7
        MVII #_keypad_table,R4
    REPEAT 6
        CMP@ R4,R0
        BEQ @@7
	CMP@ R4,R0
	BEQ @@7
    ENDR

	INCR R4
@@7:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt2_key

@@5:    MVI _cnt2_p1,R1
        MVO R1,_cnt2_p0
        MVO R0,_cnt2_p1
    ENDI

        CLRR    R0
        MVO     R0,_int         ; Clears waiting flag
@@1:    CMP     _int,  R0       ; Waits for change
        BEQ     @@1
        JR      R5              ; Returns
        ENDP

        ;
        ; Keypad table
        ;
_keypad_table:          PROC
        DECLE $48,$81,$41,$21,$82,$42,$22,$84,$44,$24,$88,$28
        ENDP

_pal1_vector:    PROC
        MVII #_pal2_vector,R0
        MVO R0,ISRVEC
        SWAP R0
        MVO R0,ISRVEC+1
        MVII #3,R0
        MVO R0,_ntsc
        JR R5
        ENDP

_pal2_vector:    PROC
        MVII #_int_vector,R0     ; Point to "real" interruption handler
        MVO R0,ISRVEC
        SWAP R0
        MVO R0,ISRVEC+1
        MVII #4,R0
        MVO R0,_ntsc
	CLRR R0
	CLRR R4
	MVII #$18,R1
@@1:	MVO@ R0,R4
	DECR R1
	BNE @@1
        JR R5
        ENDP

        ;
        ; Interruption routine
        ;
_int_vector:     PROC
        BEGIN

        MVO     R0,     $20     ; Activates display

    IF DEFINED intybasic_stack
	CMPI #$308,R6
	BNC @@vs
	MVI $21,R0	; Activates Color Stack mode
	CLRR R0
	MVO R0,$28
	MVO R0,$29
	MVO R0,$2A
	MVO R0,$2B
	MVII #@@vs1,R4
	MVII #$200,R5
	MVII #20,R1
@@vs2:	MVI@ R4,R0
	MVO@ R0,R5
	DECR R1
	BNE @@vs2
	RETURN

	; Stack Overflow message
@@vs1:	DECLE 0,0,0,$33*8+7,$54*8+7,$41*8+7,$43*8+7,$4B*8+7,$00*8+7
	DECLE $4F*8+7,$56*8+7,$45*8+7,$52*8+7,$46*8+7,$4C*8+7
	DECLE $4F*8+7,$57*8+7,0,0,0

@@vs:
    ENDI
        MVII    #1,     R0
        MVO     R0,     _int    ; Indicates interrupt happened

        MVI _mode_select,R0
        TSTR R0
        BEQ @@vi0
        CLRR R1
        MVO R1,_mode_select
        DECR R0
        BEQ @@vi14
        MVO R0,$21  ; Activates Foreground/Background mode
        B @@vi15

@@vi14: MVI $21,R0  ; Activates Color Stack mode
        MVI _color,R0
        MVO R0,$28
        SWAP R0
        MVO R0,$29
        SLR R0,2
        SLR R0,2
        MVO R0,$2A
        SWAP R0
        MVO R0,$2B
@@vi15: MVII #7,R0
        MVO R0,_color           ; Default color for PRINT "string"
@@vi0:
        MVI _border_color,R0
        MVO     R0,     $2C     ; Border color
        MVI _border_mask,R0
        MVO     R0,     $32     ; Border mask
        ;
        ; Save collision registers for further use and clear them
        ;
        MVII #$18,R4
        MVII #_col0,R5
        MVI@ R4,R0
        MVO@ R0,R5  ; _col0
        MVI@ R4,R0
        MVO@ R0,R5  ; _col1
        MVI@ R4,R0
        MVO@ R0,R5  ; _col2
        MVI@ R4,R0
        MVO@ R0,R5  ; _col3
        MVI@ R4,R0
        MVO@ R0,R5  ; _col4
        MVI@ R4,R0
        MVO@ R0,R5  ; _col5
        MVI@ R4,R0
        MVO@ R0,R5  ; _col6
        MVI@ R4,R0
        MVO@ R0,R5  ; _col7
        MVII #$18,R5
        CLRR R0
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        
    IF DEFINED intybasic_scroll

        ;
        ; Scrolling things
        ;
        MVI _scroll_x,R0
        MVO R0,$30
        MVI _scroll_y,R0
        MVO R0,$31
    ENDI

        ;
        ; Updates sprites (MOBs)
        ;
        MVII #_mobs,R4
        MVII #$0,R5     ; X-coordinates
        MVII #8,R1
@@vi2:  MVI@ R4,R0
        MVO@ R0,R5
        MVI@ R4,R0
        MVO@ R0,R5
        MVI@ R4,R0
        MVO@ R0,R5
        DECR R1
        BNE @@vi2

    IF DEFINED intybasic_music
     	MVI _ntsc,R0
        TSTR R0         ; PAL?
        BEQ @@vo97      ; Yes, always emit sound
	MVI _music_frame,R0
	INCR R0
	CMPI #6,R0
	BNE @@vo14
	CLRR R0
@@vo14:	MVO R0,_music_frame
	BEQ @@vo15
@@vo97:	CALL _emit_sound
@@vo15:
    ENDI

        ;
        ; Detect GRAM definition
        ;
        MVI _gram_bitmap,R4
        TSTR R4
        BEQ @@vi1
        MVI _gram_target,R1
        SLL R1,2
        SLL R1,1
        ADDI #$3800,R1
        MOVR R1,R5
        MVI _gram_total,R0
@@vi3:
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        DECR R0
        BNE @@vi3
        MVO R0,_gram_bitmap
@@vi1:
        MVI _gram2_bitmap,R4
        TSTR R4
        BEQ @@vii1
        MVI _gram2_target,R1
        SLL R1,2
        SLL R1,1
        ADDI #$3800,R1
        MOVR R1,R5
        MVI _gram2_total,R0
@@vii3:
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        DECR R0
        BNE @@vii3
        MVO R0,_gram2_bitmap
@@vii1:

    IF DEFINED intybasic_scroll
        ;
        ; Frame scroll support
        ;
        MVI _scroll_d,R0
        TSTR R0
        BEQ @@vi4
        CLRR R1
        MVO R1,_scroll_d
        DECR R0     ; Left
        BEQ @@vi5
        DECR R0     ; Right
        BEQ @@vi6
        DECR R0     ; Top
        BEQ @@vi7
        DECR R0     ; Bottom
        BEQ @@vi8
        B @@vi4

@@vi5:  MVII #$0200,R4
        MOVR R4,R5
        INCR R5
        MVII #12,R1
@@vi12: MVI@ R4,R2
        MVI@ R4,R3
        REPEAT 8
        MVO@ R2,R5
        MVI@ R4,R2
        MVO@ R3,R5
        MVI@ R4,R3
        ENDR
        MVO@ R2,R5
        MVI@ R4,R2
        MVO@ R3,R5
        MVO@ R2,R5
        INCR R4
        INCR R5
        DECR R1
        BNE @@vi12
        B @@vi4

@@vi6:  MVII #$0201,R4
        MVII #$0200,R5
        MVII #12,R1
@@vi11:
        REPEAT 19
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        INCR R4
        INCR R5
        DECR R1
        BNE @@vi11
        B @@vi4
    
        ;
        ; Complex routine to be ahead of STIC display
        ; Moves first the top 6 lines, saves intermediate line
        ; Then moves the bottom 6 lines and restores intermediate line
        ;
@@vi7:  MVII #$0264,R4
        MVII #5,R1
        MVII #_scroll_buffer,R5
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        SUBI #40,R4
        MOVR R4,R5
        ADDI #20,R5
@@vi10:
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        SUBI #40,R4
        SUBI #40,R5
        DECR R1
        BNE @@vi10
        MVII #$02C8,R4
        MVII #$02DC,R5
        MVII #5,R1
@@vi13:
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        SUBI #40,R4
        SUBI #40,R5
        DECR R1
        BNE @@vi13
        MVII #_scroll_buffer,R4
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        B @@vi4

@@vi8:  MVII #$0214,R4
        MVII #$0200,R5
        MVII #$DC/4,R1
@@vi9:  
        REPEAT 4
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        DECR R1
        BNE @@vi9
        B @@vi4

@@vi4:
    ENDI

    IF DEFINED intybasic_voice
        ;
        ; Intellivoice support
        ;
        CALL IV_ISR
    ENDI

        ;
        ; Random number generator
        ;
	CALL _next_random

    IF DEFINED intybasic_music
	; Generate sound for next frame
       	MVI _ntsc,R0
        TSTR R0         ; PAL?
        BEQ @@vo98      ; Yes, always generate sound
	MVI _music_frame,R0
	TSTR R0
	BEQ @@vo16
@@vo98: CALL _generate_music
@@vo16:
    ENDI

        ; Increase frame number
        MVI _frame,R0
        INCR R0
        MVO R0,_frame

	; This mark is for ON FRAME GOSUB support

        RETURN
        ENDP

	;
	; Generates the next random number
	;
_next_random:	PROC

MACRO _ROR
	RRC R0,1
	MOVR R0,R2
	SLR R2,2
	SLR R2,2
	ANDI #$0800,R2
	SLR R2,2
	SLR R2,2
	ANDI #$007F,R0
	XORR R2,R0
ENDM
        MVI _rand,R0
        SETC
        _ROR
        XOR _frame,R0
        _ROR
        XOR _rand,R0
        _ROR
        XORI #9,R0
        MVO R0,_rand
	JR R5
	ENDP

    IF DEFINED intybasic_music

        ;
        ; Music player, comes from my game Princess Quest for Intellivision
        ; so it's a practical tracker used in a real game ;) and with enough
        ; features.
        ;

        ; NTSC frequency for notes (based on 3.579545 mhz)
ntsc_note_table:    PROC
        ; Silence - 0
        DECLE 0
        ; Octave 2 - 1
        DECLE 1721,1621,1532,1434,1364,1286,1216,1141,1076,1017,956,909
        ; Octave 3 - 13
        DECLE 854,805,761,717,678,639,605,571,538,508,480,453
        ; Octave 4 - 25
        DECLE 427,404,380,360,339,321,302,285,270,254,240,226
        ; Octave 5 - 37
        DECLE 214,202,191,180,170,160,151,143,135,127,120,113
        ; Octave 6 - 49
        DECLE 107,101,95,90,85,80,76,71,67,64,60,57
        ; Octave 7 - 61
        ; Space for two notes more
	ENDP

        ; PAL frequency for notes (based on 4 mhz)
pal_note_table:    PROC
        ; Silence - 0
        DECLE 0
        ; Octava 2 - 1
        DECLE 1923,1812,1712,1603,1524,1437,1359,1276,1202,1136,1068,1016
        ; Octava 3 - 13
        DECLE 954,899,850,801,758,714,676,638,601,568,536,506
        ; Octava 4 - 25
        DECLE 477,451,425,402,379,358,338,319,301,284,268,253
        ; Octava 5 - 37
        DECLE 239,226,213,201,190,179,169,159,150,142,134,127
        ; Octava 6 - 49
        DECLE 120,113,106,100,95,89,84,80,75,71,67,63
        ; Octava 7 - 61
        ; Space for two notes more
	ENDP
    ENDI

        ;
        ; Music tracker init
        ;
_init_music:	PROC
    IF DEFINED intybasic_music
        MVI _ntsc,R0
        CMPI #1,R0
        MVII #ntsc_note_table,R0
        BEQ @@0
        MVII #pal_note_table,R0
@@0:    MVO R0,_music_table
        MVII #$38,R0	; $B8 blocks controllers o.O!
	MVO R0,_music_mix
        CLRR R0
    ELSE
	JR R5
    ENDI
	ENDP

    IF DEFINED intybasic_music
        ;
        ; Start music
        ; R0 = Pointer to music
        ;
_play_music:	PROC
	MOVR R0,R2
        MVII #1,R0
	MOVR R0,R3
	TSTR R2
	BEQ @@1
	MVI@ R2,R3
	INCR R2
@@1:	MVO R2,_music_start
	MVO R2,_music_p
	MVO R3,_music_t
	MVO R0,_music_tc
        JR R5

	ENDP

        ;
        ; Generate music
        ;
_generate_music:	PROC
	BEGIN
	MVI _music_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music_mix
	CLRR R1			; Turn off volume for the three sound channels
	MVO R1,_music_vol1
	MVO R1,_music_vol2
	NOP
	MVO R1,_music_vol3
	MVI _music_tc,R3
	DECR R3
	MVO R3,_music_tc
	BNE @@6
	; R3 is zero from here up to @@6
	MVI _music_p,R4
@@15:	TSTR R4		; Silence?
	BEQ @@000	; Keep quiet
	MVI@ R4,R0
	MVI@ R4,R1
	MVI _music_t,R2
        CMPI #$FE,R0	; The end?
	BEQ @@001       ; Keep quiet
	CMPI #$FD,R0	; Repeat?
	BNE @@00
	MVI _music_start,R4
	B @@15

@@001:	MOVR R1,R4	; Jump, zero will make it quiet
	B @@15

@@000:  MVII #1,R0
        MVO R0,_music_tc
        B @@0
        
@@00: 	MVO R2,_music_tc    ; Restart note time
     	MVO R4,_music_p
     	
	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@1
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n1	; Note
	MVO R3,_music_s1	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i1	; Instrument
	
@@1:	MOVR R0,R2
	SWAP R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@2
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n2	; Note
	MVO R3,_music_s2	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i2	; Instrument
	
@@2:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@3
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n3	; Note
	MVO R3,_music_s3	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i3	; Instrument
	
@@3:	MOVR R1,R2
	SWAP R2
	MVO R2,_music_n4
	MVO R3,_music_s4
	
        ;
        ; Construct main voice
        ;
@@6:	MVI _music_n1,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@7		; No, jump
	MVI _music_s1,R1
	MVI _music_i1,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music_freq11
	MVO R1,_music_vol1
        ; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@20
	SUBI #$08,R0
@@20:	MVO R0,_music_s1

@@7:	MVI _music_n2,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@8		; No, jump
	MVI _music_s2,R1
	MVI _music_i2,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music_freq21
	MVO R1,_music_vol2
        ; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@21
	SUBI #$08,R0
@@21:	MVO R0,_music_s2

@@8:	MVI _music_n3,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@9		; No, jump
	MVI _music_s3,R1
	MVI _music_i3,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music_freq31
	MVO R1,_music_vol3
        ; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@22
	SUBI #$08,R0
@@22:	MVO R0,_music_s3

@@9:	MVI _music_n4,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@4		; No, jump
	MVI _music_s4,R1
	       		; 1 - Strong
	BNE @@5
	CMPI #3,R1
	BGE @@12
@@10:	MVII #5,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@5:	DECR R0		;2 - Short
	BNE @@11
	TSTR R1
	BNE @@12
	MVII #8,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@11:	;DECR R0	; 3 - Rolling
	;BNE @@12
	CMPI #2,R1
	BLT @@10
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@12
        ADDI #2,R0
	CMPR R0,R1
	BLT @@10
        ; Increase time for drum waveform
@@12:   INCR R1
	MVO R1,_music_s4
@@4:
@@0:	RETURN
	ENDP

        ;
	; Translates note number to frequency
        ; R3 = Note
        ; R1 = Position in waveform for instrument
        ; R2 = Instrument
        ;
_note2freq:	PROC
        ADD _music_table,R3
	MVI@ R3,R3
        SWAP R2
	BEQ _piano_instrument
	RLC R2,1
	BNC _clarinet_instrument
	BPL _flute_instrument
;	BMI _bass_instrument
	ENDP

        ;
        ; Generates a bass
        ;
_bass_instrument:	PROC
	SLL R3,2	; Lower 2 octaves
	ADDI #_bass_volume,R1
	MVI@ R1,R1	; Bass effect
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_bass_volume:	PROC
        DECLE 12,13,14,14,13,12,12,12
        DECLE 11,11,12,12,11,11,12,12
	DECLE 11,11,12,12,11,11,12,12
	ENDP

        ;
        ; Generates a piano
        ; R3 = Frequency
        ; R1 = Waveform position
        ;
        ; Output:
        ; R3 = Frequency.
        ; R1 = Volume.
        ;
_piano_instrument:	PROC
	ADDI #_piano_volume,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_piano_volume:	PROC
        DECLE 14,13,13,12,12,11,11,10
        DECLE 10,9,9,8,8,7,7,6
        DECLE 6,6,7,7,6,6,5,5
	ENDP

        ;
        ; Generate a clarinet
        ; R3 = Frequency
        ; R1 = Waveform position
        ;
        ; Output:
        ; R3 = Frequency
        ; R1 = Volume
        ;
_clarinet_instrument:	PROC
	ADDI #_clarinet_vibrato,R1
	ADD@ R1,R3
	CLRC
	RRC R3,1	; Duplicates frequency
	ADCR R3
        ADDI #_clarinet_volume-_clarinet_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_clarinet_vibrato:	PROC
        DECLE 0,0,0,0
        DECLE -2,-4,-2,0
        DECLE 2,4,2,0
        DECLE -2,-4,-2,0
        DECLE 2,4,2,0
        DECLE -2,-4,-2,0
	ENDP

_clarinet_volume:	PROC
        DECLE 13,14,14,13,13,12,12,12
        DECLE 11,11,11,11,12,12,12,12
        DECLE 11,11,11,11,12,12,12,12
	ENDP

        ;
        ; Generates a flute
        ; R3 = Frequency
        ; R1 = Waveform position
        ;
        ; Output:
        ; R3 = Frequency
        ; R1 = Volume
        ;
_flute_instrument:	PROC
	ADDI #_flute_vibrato,R1
	ADD@ R1,R3
	ADDI #_flute_volume-_flute_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_flute_vibrato:	PROC
        DECLE 0,0,0,0
        DECLE 0,1,2,1
        DECLE 0,1,2,1
        DECLE 0,1,2,1
        DECLE 0,1,2,1
        DECLE 0,1,2,1
	ENDP
                 
_flute_volume:	PROC
        DECLE 10,12,13,13,12,12,12,12
        DECLE 11,11,11,11,10,10,10,10
        DECLE 11,11,11,11,10,10,10,10
	ENDP

    IF DEFINED intybasic_music_volume

_global_volume:	PROC
	MVI _music_vol,R2
	ANDI #$0F,R2
	SLL R2,2
	SLL R2,2
	ADDR R1,R2
	ADDI #@@table,R2
	MVI@ R2,R1
	JR R5

@@table:
	DECLE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	DECLE 0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1
	DECLE 0,0,0,0,1,1,1,1,1,1,1,2,2,2,2,2
	DECLE 0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3
	DECLE 0,0,1,1,1,1,2,2,2,2,3,3,3,4,4,4
	DECLE 0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5
	DECLE 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6
	DECLE 0,1,1,1,2,2,3,3,4,4,5,5,6,6,7,7
	DECLE 0,1,1,2,2,3,3,4,4,5,5,6,6,7,8,8
	DECLE 0,1,1,2,2,3,4,4,5,5,6,7,7,8,8,9
	DECLE 0,1,1,2,3,3,4,5,5,6,7,7,8,9,9,10
	DECLE 0,1,2,2,3,4,4,5,6,7,7,8,9,10,10,11
	DECLE 0,1,2,2,3,4,5,6,6,7,8,9,10,10,11,12
	DECLE 0,1,2,3,4,4,5,6,7,8,9,10,10,11,12,13
	DECLE 0,1,2,3,4,5,6,7,8,8,9,10,11,12,13,14
	DECLE 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

	ENDP

    ENDI

        ;
        ; Emits sound
        ;
_emit_sound:	PROC
        MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music_freq10,R4
	MVII #$01F0,R5
        MVI@ R4,R0
	MVO@ R0,R5	; $01F0 - Channel A Period (Low 8 bits of 12)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F1 - Channel B Period (Low 8 bits of 12)
	DECR R2
	BEQ @@1
        MVI@ R4,R0	
	MVO@ R0,R5	; $01F2 - Channel C Period (Low 8 bits of 12)
	INCR R5		; Avoid $01F3 - Enveloped Period (Low 8 bits of 16)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F6 - Channel C Period (High 4 bits of 12)
	INCR R5		; Avoid $01F7 - Envelope Period (High 8 bits of 16)
	BC @@2		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@3

@@2:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
        MVI@ R4,R0	
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@3:    MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
        MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
        MVI@ R4,R0
	MVO@ R0,R5	; $01FD - Channel C Volume
        JR R1

@@1:	INCR R4		
	ADDI #2,R5	; Avoid $01F2 and $01F3
        MVI@ R4,R0
	MVO@ R0,R5	; $01F4
        MVI@ R4,R0
	MVO@ R0,R5	; $01F5
	INCR R4
	ADDI #2,R5	; Avoid $01F6 and $01F7
	BC @@4		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@5

@@4:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8
        MVI@ R4,R0
	MVO@ R0,R5	; $01F9
	INCR R5		; Avoid $01FA
@@5:    MVI@ R4,R0
	MVO@ R0,R5	; $01FB
        MVI@ R4,R0
	MVO@ R0,R5	; $01FD
@@6:    JR R1
	ENDP

        ;
        ; Activates drum
        ;
_activate_drum:	PROC
    IF DEFINED intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music_vol1,R0
	TSTR R0
	BNE @@1
        MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol1
	MVI _music_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music_vol2,R0
	TSTR R0
	BNE @@2
        MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol2
	MVI _music_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
        BEQ @@3		; Yes, jump
        MVI _music_vol3,R0
	TSTR R0
	BNE @@3
        MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol3
	MVI _music_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music_mix,R0
        ANDI #$EF,R0
	MVO R0,_music_mix
@@0:	
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    ENDI
    
    IF DEFINED intybasic_numbers

	;
	; Following code from as1600 libraries, prnum16.asm
        ; Public domain by Joseph Zbiciak
	;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008                                     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  _PW10                                                                   ;;
;;      Lookup table holding the first 5 powers of 10 (1 thru 10000) as     ;;
;;      16-bit numbers.                                                     ;;
;; ======================================================================== ;;
_PW10   PROC    ; 0 thru 10000
        DECLE   10000, 1000, 100, 10, 1, 0
        ENDP

;; ======================================================================== ;;
;;  PRNUM16.l     -- Print an unsigned 16-bit number left-justified.        ;;
;;  PRNUM16.b     -- Print an unsigned 16-bit number with leading blanks.   ;;
;;  PRNUM16.z     -- Print an unsigned 16-bit number with leading zeros.    ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak  <im14u2c AT globalcrossing DOT net>                 ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      30-Mar-2003 Initial complete revision                               ;;
;;                                                                          ;;
;;  INPUTS for all variants                                                 ;;
;;      R0  Number to print.                                                ;;
;;      R2  Width of field.  Ignored by PRNUM16.l.                          ;;
;;      R3  Format word, added to digits to set the color.                  ;;
;;          Note:  Bit 15 MUST be cleared when building with PRNUM32.       ;;
;;      R4  Pointer to location on screen to print number                   ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0  Zeroed                                                          ;;
;;      R1  Unmodified                                                      ;;
;;      R2  Unmodified                                                      ;;
;;      R3  Unmodified                                                      ;;
;;      R4  Points to first character after field.                          ;;
;;                                                                          ;;
;;  DESCRIPTION                                                             ;;
;;      These routines print unsigned 16-bit numbers in a field up to 5     ;;
;;      positions wide.  The number is printed either in left-justified     ;;
;;      or right-justified format.  Right-justified numbers are padded      ;;
;;      with leading blanks or leading zeros.  Left-justified numbers       ;;
;;      are not padded on the right.                                        ;;
;;                                                                          ;;
;;      This code handles fields wider than 5 characters, padding with      ;;
;;      zeros or blanks as necessary.                                       ;;
;;                                                                          ;;
;;              Routine      Value(hex)     Field        Output             ;;
;;              ----------   ----------   ----------   ----------           ;;
;;              PRNUM16.l      $0045         n/a        "69"                ;;
;;              PRNUM16.b      $0045          4         "  69"              ;;
;;              PRNUM16.b      $0045          6         "    69"            ;;
;;              PRNUM16.z      $0045          4         "0069"              ;;
;;              PRNUM16.z      $0045          6         "000069"            ;;
;;                                                                          ;;
;;  TECHNIQUES                                                              ;;
;;      This routine uses repeated subtraction to divide the number         ;;
;;      to display by various powers of 10.  This is cheaper than a         ;;
;;      full divide, at least when the input number is large.  It's         ;;
;;      also easier to get right.  :-)                                      ;;
;;                                                                          ;;
;;      The printing routine first pads out fields wider than 5 spaces      ;;
;;      with zeros or blanks as requested.  It then scans the power-of-10   ;;
;;      table looking for the first power of 10 that is <= the number to    ;;
;;      display.  While scanning for this power of 10, it outputs leading   ;;
;;      blanks or zeros, if requested.  This eliminates "leading digit"     ;;
;;      logic from the main digit loop.                                     ;;
;;                                                                          ;;
;;      Once in the main digit loop, we discover the value of each digit    ;;
;;      by repeated subtraction.  We build up our digit value while         ;;
;;      subtracting the power-of-10 repeatedly.  We iterate until we go     ;;
;;      a step too far, and then we add back on power-of-10 to restore      ;;
;;      the remainder.                                                      ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      The left-justified variant ignores field width.                     ;;
;;                                                                          ;;
;;      The code is fully reentrant.                                        ;;
;;                                                                          ;;
;;      This code does not handle numbers which are too large to be         ;;
;;      displayed in the provided field.  If the number is too large,       ;;
;;      non-digit characters will be displayed in the initial digit         ;;
;;      position.  Also, the run time of this routine may get excessively   ;;
;;      large, depending on the magnitude of the overflow.                  ;;
;;                                                                          ;;
;;      When using with PRNUM32, one must either include PRNUM32 before     ;;
;;      this function, or define the symbol _WITH_PRNUM32.  PRNUM32         ;;
;;      needs a tiny bit of support from PRNUM16 to handle numbers in       ;;
;;      the range 65536...99999 correctly.                                  ;;
;;                                                                          ;;
;;  CODESIZE                                                                ;;
;;      73 words, including power-of-10 table                               ;;
;;      80 words, if compiled with PRNUM32.                                 ;;
;;                                                                          ;;
;;      To save code size, you can define the following symbols to omit     ;;
;;      some variants:                                                      ;;
;;                                                                          ;;
;;          _NO_PRNUM16.l:   Disables PRNUM16.l.  Saves 10 words            ;;
;;          _NO_PRNUM16.b:   Disables PRNUM16.b.  Saves 3 words.            ;;
;;                                                                          ;;
;;      Defining both symbols saves 17 words total, because it omits        ;;
;;      some code shared by both routines.                                  ;;
;;                                                                          ;;
;;  STACK USAGE                                                             ;;
;;      This function uses up to 4 words of stack space.                    ;;
;; ======================================================================== ;;

PRNUM16 PROC

    
        ;; ---------------------------------------------------------------- ;;
        ;;  PRNUM16.l:  Print unsigned, left-justified.                     ;;
        ;; ---------------------------------------------------------------- ;;
@@l:    PSHR    R5              ; save return address
@@l1:   MVII    #$1,    R5      ; set R5 to 1 to counteract screen ptr update
                                ; in the 'find initial power of 10' loop
        PSHR    R2
        MVII    #5,     R2      ; force effective field width to 5.
        B       @@z2

        ;; ---------------------------------------------------------------- ;;
        ;;  PRNUM16.b:  Print unsigned with leading blanks.                 ;;
        ;; ---------------------------------------------------------------- ;;
@@b:    PSHR    R5
@@b1:   CLRR    R5              ; let the blank loop do its thing
        INCR    PC              ; skip the PSHR R5

        ;; ---------------------------------------------------------------- ;;
        ;;  PRNUM16.z:  Print unsigned with leading zeros.                  ;;
        ;; ---------------------------------------------------------------- ;;
@@z:    PSHR    R5
@@z1:   PSHR    R2
@@z2:   PSHR    R1

        ;; ---------------------------------------------------------------- ;;
        ;;  Find the initial power of 10 to use for display.                ;;
        ;;  Note:  For fields wider than 5, fill the extra spots above 5    ;;
        ;;  with blanks or zeros as needed.                                 ;;
        ;; ---------------------------------------------------------------- ;;
        MVII    #_PW10+5,R1     ; Point to end of power-of-10 table
        SUBR    R2,     R1      ; Subtract the field width to get right power
        PSHR    R3              ; save format word

        CMPI    #2,     R5      ; are we leading with zeros?
        BNC     @@lblnk         ; no:  then do the loop w/ blanks

        CLRR    R5              ; force R5==0
        ADDI    #$80,   R3      ; yes: do the loop with zeros
        B       @@lblnk
    

@@llp   MVO@    R3,     R4      ; print a blank/zero

        SUBR    R5,     R4      ; rewind pointer if needed.

        INCR    R1              ; get next power of 10
@@lblnk DECR    R2              ; decrement available digits
        BEQ     @@ldone
        CMPI    #5,     R2      ; field too wide?
        BGE     @@llp           ; just force blanks/zeros 'till we're narrower.
        CMP@    R1,     R0      ; Is this power of 10 too big?
        BNC     @@llp           ; Yes:  Put a blank and go to next

@@ldone PULR    R3              ; restore format word

        ;; ---------------------------------------------------------------- ;;
        ;;  The digit loop prints at least one digit.  It discovers digits  ;;
        ;;  by repeated subtraction.                                        ;;
        ;; ---------------------------------------------------------------- ;;
@@digit TSTR    R0              ; If the number is zero, print zero and leave
        BNEQ    @@dig1          ; no: print the number

        MOVR    R3,     R5      ;\    
        ADDI    #$80,   R5      ; |-- print a 0 there.
        MVO@    R5,     R4      ;/    
        B       @@done

@@dig1:
    
@@nxdig MOVR    R3,     R5      ; save display format word
@@cont: ADDI    #$80-8, R5      ; start our digit as one just before '0'
@@spcl:
 
        ;; ---------------------------------------------------------------- ;;
        ;;  Divide by repeated subtraction.  This divide is constructed     ;;
        ;;  to go "one step too far" and then back up.                      ;;
        ;; ---------------------------------------------------------------- ;;
@@div:  ADDI    #8,     R5      ; increment our digit
        SUB@    R1,     R0      ; subtract power of 10
        BC      @@div           ; loop until we go too far
        ADD@    R1,     R0      ; add back the extra power of 10.

        MVO@    R5,     R4      ; display the digit.

        INCR    R1              ; point to next power of 10
        DECR    R2              ; any room left in field?
        BPL     @@nxdig         ; keep going until R2 < 0.

@@done: PULR    R1              ; restore R1
        PULR    R2              ; restore R2
        PULR    PC              ; return

        ENDP
        
    ENDI

    IF DEFINED intybasic_voice
;;==========================================================================;;
;;  SP0256-AL2 Allophones                                                   ;;
;;                                                                          ;;
;;  This file contains the allophone set that was obtained from an          ;;
;;  SP0256-AL2.  It is being provided for your convenience.                 ;;
;;                                                                          ;;
;;  The directory "al2" contains a series of assembly files, each one       ;;
;;  containing a single allophone.  This series of files may be useful in   ;;
;;  situations where space is at a premium.                                 ;;
;;                                                                          ;;
;;  Consult the Archer SP0256-AL2 documentation (under doc/programming)     ;;
;;  for more information about SP0256-AL2's allophone library.              ;;
;;                                                                          ;;
;; ------------------------------------------------------------------------ ;;
;;                                                                          ;;
;;  Copyright information:                                                  ;;
;;                                                                          ;;
;;  The allophone data below was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is           ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY         ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.                                       ;;
;;                                                                          ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms        ;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.                                   ;;
;;                                                                          ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;                                                                          ;;
;;==========================================================================;;

;; ------------------------------------------------------------------------ ;;
_AA:
    DECLE   _AA.end - _AA - 1
    DECLE   $0318, $014C, $016F, $02CE, $03AF, $015F, $01B1, $008E
    DECLE   $0088, $0392, $01EA, $024B, $03AA, $039B, $000F, $0000
_AA.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_AE1:
    DECLE   _AE1.end - _AE1 - 1
    DECLE   $0118, $038E, $016E, $01FC, $0149, $0043, $026F, $036E
    DECLE   $01CC, $0005, $0000
_AE1.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AO:
    DECLE   _AO.end - _AO - 1
    DECLE   $0018, $010E, $016F, $0225, $00C6, $02C4, $030F, $0160
    DECLE   $024B, $0005, $0000
_AO.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AR:
    DECLE   _AR.end - _AR - 1
    DECLE   $0218, $010C, $016E, $001E, $000B, $0091, $032F, $00DE
    DECLE   $018B, $0095, $0003, $0238, $0027, $01E0, $03E8, $0090
    DECLE   $0003, $01C7, $0020, $03DE, $0100, $0190, $01CA, $02AB
    DECLE   $00B7, $004A, $0386, $0100, $0144, $02B6, $0024, $0320
    DECLE   $0011, $0041, $01DF, $0316, $014C, $016E, $001E, $00C4
    DECLE   $02B2, $031E, $0264, $02AA, $019D, $01BE, $000B, $00F0
    DECLE   $006A, $01CE, $00D6, $015B, $03B5, $03E4, $0000, $0380
    DECLE   $0007, $0312, $03E8, $030C, $016D, $02EE, $0085, $03C2
    DECLE   $03EC, $0283, $024A, $0005, $0000
_AR.end:  ; 69 decles
;; ------------------------------------------------------------------------ ;;
_AW:
    DECLE   _AW.end - _AW - 1
    DECLE   $0010, $01CE, $016E, $02BE, $0375, $034F, $0220, $0290
    DECLE   $008A, $026D, $013F, $01D5, $0316, $029F, $02E2, $018A
    DECLE   $0170, $0035, $00BD, $0000, $0000
_AW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_AX:
    DECLE   _AX.end - _AX - 1
    DECLE   $0218, $02CD, $016F, $02F5, $0386, $00C2, $00CD, $0094
    DECLE   $010C, $0005, $0000
_AX.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AY:
    DECLE   _AY.end - _AY - 1
    DECLE   $0110, $038C, $016E, $03B7, $03B3, $02AF, $0221, $009E
    DECLE   $01AA, $01B3, $00BF, $02E7, $025B, $0354, $00DA, $017F
    DECLE   $018A, $03F3, $00AF, $02D5, $0356, $027F, $017A, $01FB
    DECLE   $011E, $01B9, $03E5, $029F, $025A, $0076, $0148, $0124
    DECLE   $003D, $0000
_AY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_BB1:
    DECLE   _BB1.end - _BB1 - 1
    DECLE   $0318, $004C, $016C, $00FB, $00C7, $0144, $002E, $030C
    DECLE   $010E, $018C, $01DC, $00AB, $00C9, $0268, $01F7, $021D
    DECLE   $01B3, $0098, $0000
_BB1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_BB2:
    DECLE   _BB2.end - _BB2 - 1
    DECLE   $00F4, $0046, $0062, $0200, $0221, $03E4, $0087, $016F
    DECLE   $02A6, $02B7, $0212, $0326, $0368, $01BF, $0338, $0196
    DECLE   $0002
_BB2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_CH:
    DECLE   _CH.end - _CH - 1
    DECLE   $00F5, $0146, $0052, $0000, $032A, $0049, $0032, $02F2
    DECLE   $02A5, $0000, $026D, $0119, $0124, $00F6, $0000
_CH.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_DD1:
    DECLE   _DD1.end - _DD1 - 1
    DECLE   $0318, $034C, $016E, $0397, $01B9, $0020, $02B1, $008E
    DECLE   $0349, $0291, $01D8, $0072, $0000
_DD1.end:  ; 13 decles
;; ------------------------------------------------------------------------ ;;
_DD2:
    DECLE   _DD2.end - _DD2 - 1
    DECLE   $00F4, $00C6, $00F2, $0000, $0129, $00A6, $0246, $01F3
    DECLE   $02C6, $02B7, $028E, $0064, $0362, $01CF, $0379, $01D5
    DECLE   $0002
_DD2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_DH1:
    DECLE   _DH1.end - _DH1 - 1
    DECLE   $0018, $034F, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_DH2:
    DECLE   _DH2.end - _DH2 - 1
    DECLE   $0119, $034C, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_EH:
    DECLE   _EH.end - _EH - 1
    DECLE   $0218, $02CD, $016F, $0105, $014B, $0224, $02CF, $0274
    DECLE   $014C, $0005, $0000
_EH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_EL:
    DECLE   _EL.end - _EL - 1
    DECLE   $0118, $038D, $016E, $011C, $008B, $03D2, $030F, $0262
    DECLE   $006C, $019D, $01CC, $022B, $0170, $0078, $03FE, $0018
    DECLE   $0183, $03A3, $010D, $016E, $012E, $00C6, $00C3, $0300
    DECLE   $0060, $000D, $0005, $0000
_EL.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_ER1:
    DECLE   _ER1.end - _ER1 - 1
    DECLE   $0118, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0188
    DECLE   $01DA, $00CB, $00E7, $0048, $03A6, $0244, $016C, $01A8
    DECLE   $03E4, $0000, $0002, $0001, $00FC, $01DA, $02E4, $0000
    DECLE   $0002, $0008, $0200, $0217, $0164, $0000, $000E, $0038
    DECLE   $0014, $01EA, $0264, $0000, $0002, $0048, $01EC, $02F1
    DECLE   $03CC, $016D, $021E, $0048, $00C2, $034E, $036A, $000D
    DECLE   $008D, $000B, $0200, $0047, $0022, $03A8, $0000, $0000
_ER1.end:  ; 64 decles
;; ------------------------------------------------------------------------ ;;
_ER2:
    DECLE   _ER2.end - _ER2 - 1
    DECLE   $0218, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0190
    DECLE   $01D8, $00CB, $00E7, $0058, $01A6, $0244, $0164, $02A9
    DECLE   $0024, $0000, $0000, $0007, $0201, $02F8, $02E4, $0000
    DECLE   $0002, $0001, $00FC, $02DA, $0024, $0000, $0002, $0008
    DECLE   $0200, $0217, $0024, $0000, $000E, $0038, $0014, $03EA
    DECLE   $03A4, $0000, $0002, $0048, $01EC, $03F1, $038C, $016D
    DECLE   $021E, $0048, $00C2, $034E, $036A, $000D, $009D, $0003
    DECLE   $0200, $0047, $0022, $03A8, $0000, $0000
_ER2.end:  ; 70 decles
;; ------------------------------------------------------------------------ ;;
_EY:
    DECLE   _EY.end - _EY - 1
    DECLE   $0310, $038C, $016E, $02A7, $00BB, $0160, $0290, $0094
    DECLE   $01CA, $03A9, $00C1, $02D7, $015B, $01D4, $03CE, $02FF
    DECLE   $00EA, $03E7, $0041, $0277, $025B, $0355, $03C9, $0103
    DECLE   $02EA, $03E4, $003F, $0000
_EY.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_FF:
    DECLE   _FF.end - _FF - 1
    DECLE   $0119, $03C8, $0000, $00A7, $0094, $0138, $01C6, $0000
_FF.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_GG1:
    DECLE   _GG1.end - _GG1 - 1
    DECLE   $00F4, $00C6, $00C2, $0200, $0015, $03FE, $0283, $01FD
    DECLE   $01E6, $00B7, $030A, $0364, $0331, $017F, $033D, $0215
    DECLE   $0002
_GG1.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG2:
    DECLE   _GG2.end - _GG2 - 1
    DECLE   $00F4, $0106, $0072, $0300, $0021, $0308, $0039, $0173
    DECLE   $00C6, $00B7, $037E, $03A3, $0319, $0177, $0036, $0217
    DECLE   $0002
_GG2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG3:
    DECLE   _GG3.end - _GG3 - 1
    DECLE   $00F8, $0146, $00F2, $0100, $0132, $03A8, $0055, $01F5
    DECLE   $00A6, $02B7, $0291, $0326, $0368, $0167, $023A, $01C6
    DECLE   $0002
_GG3.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_HH1:
    DECLE   _HH1.end - _HH1 - 1
    DECLE   $0218, $01C9, $0000, $0095, $0127, $0060, $01D6, $0213
    DECLE   $0002, $01AE, $033E, $01A0, $03C4, $0122, $0001, $0218
    DECLE   $01E4, $03FD, $0019, $0000
_HH1.end:  ; 20 decles
;; ------------------------------------------------------------------------ ;;
_HH2:
    DECLE   _HH2.end - _HH2 - 1
    DECLE   $0218, $00CB, $0000, $0086, $000F, $0240, $0182, $031A
    DECLE   $02DB, $0008, $0293, $0067, $00BD, $01E0, $0092, $000C
    DECLE   $0000
_HH2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_IH:
    DECLE   _IH.end - _IH - 1
    DECLE   $0118, $02CD, $016F, $0205, $0144, $02C3, $00FE, $031A
    DECLE   $000D, $0005, $0000
_IH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_IY:
    DECLE   _IY.end - _IY - 1
    DECLE   $0318, $02CC, $016F, $0008, $030B, $01C3, $0330, $0178
    DECLE   $002B, $019D, $01F6, $018B, $01E1, $0010, $020D, $0358
    DECLE   $015F, $02A4, $02CC, $016F, $0109, $030B, $0193, $0320
    DECLE   $017A, $034C, $009C, $0017, $0001, $0200, $03C1, $0020
    DECLE   $00A7, $001D, $0001, $0104, $003D, $0040, $01A7, $01CA
    DECLE   $018B, $0160, $0078, $01F6, $0343, $01C7, $0090, $0000
_IY.end:  ; 48 decles
;; ------------------------------------------------------------------------ ;;
_JH:
    DECLE   _JH.end - _JH - 1
    DECLE   $0018, $0149, $0001, $00A4, $0321, $0180, $01F4, $039A
    DECLE   $02DC, $023C, $011A, $0047, $0200, $0001, $018E, $034E
    DECLE   $0394, $0356, $02C1, $010C, $03FD, $0129, $00B7, $01BA
    DECLE   $0000
_JH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_KK1:
    DECLE   _KK1.end - _KK1 - 1
    DECLE   $00F4, $00C6, $00D2, $0000, $023A, $03E0, $02D1, $02E5
    DECLE   $0184, $0200, $0041, $0210, $0188, $00C5, $0000
_KK1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_KK2:
    DECLE   _KK2.end - _KK2 - 1
    DECLE   $021D, $023C, $0211, $003C, $0180, $024D, $0008, $032B
    DECLE   $025B, $002D, $01DC, $01E3, $007A, $0000
_KK2.end:  ; 14 decles
;; ------------------------------------------------------------------------ ;;
_KK3:
    DECLE   _KK3.end - _KK3 - 1
    DECLE   $00F7, $0046, $01D2, $0300, $0131, $006C, $006E, $00F1
    DECLE   $00E4, $0000, $025A, $010D, $0110, $01F9, $014A, $0001
    DECLE   $00B5, $01A2, $00D8, $01CE, $0000
_KK3.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_LL:
    DECLE   _LL.end - _LL - 1
    DECLE   $0318, $038C, $016D, $029E, $0333, $0260, $0221, $0294
    DECLE   $01C4, $0299, $025A, $00E6, $014C, $012C, $0031, $0000
_LL.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_MM:
    DECLE   _MM.end - _MM - 1
    DECLE   $0210, $034D, $016D, $03F5, $00B0, $002E, $0220, $0290
    DECLE   $03CE, $02B6, $03AA, $00F3, $00CF, $015D, $016E, $0000
_MM.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_NG1:
    DECLE   _NG1.end - _NG1 - 1
    DECLE   $0118, $03CD, $016E, $00DC, $032F, $01BF, $01E0, $0116
    DECLE   $02AB, $029A, $0358, $01DB, $015B, $01A7, $02FD, $02B1
    DECLE   $03D2, $0356, $0000
_NG1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_NN1:
    DECLE   _NN1.end - _NN1 - 1
    DECLE   $0318, $03CD, $016C, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $009D, $000D, $0248, $01B4, $0120, $01E1, $00C8
    DECLE   $0003, $0040, $0000, $0080, $015F, $0006, $0000
_NN1.end:  ; 23 decles
;; ------------------------------------------------------------------------ ;;
_NN2:
    DECLE   _NN2.end - _NN2 - 1
    DECLE   $0018, $034D, $016D, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $0095, $0003, $0248, $01B4, $0120, $01E1, $0090
    DECLE   $000B, $0040, $0000, $0080, $015F, $019E, $01F6, $028B
    DECLE   $00E0, $0266, $03F6, $01D8, $0143, $01A8, $0024, $00C0
    DECLE   $0080, $0000, $01E6, $0321, $0024, $0260, $000A, $0008
    DECLE   $03FE, $0000, $0000
_NN2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_OR2:
    DECLE   _OR2.end - _OR2 - 1
    DECLE   $0218, $018C, $016D, $02A6, $03AB, $004F, $0301, $0390
    DECLE   $02EA, $0289, $0228, $0356, $01CF, $02D5, $0135, $007D
    DECLE   $02B5, $02AF, $024A, $02E2, $0153, $0167, $0333, $02A9
    DECLE   $02B3, $039A, $0351, $0147, $03CD, $0339, $02DA, $0000
_OR2.end:  ; 32 decles
;; ------------------------------------------------------------------------ ;;
_OW:
    DECLE   _OW.end - _OW - 1
    DECLE   $0310, $034C, $016E, $02AE, $03B1, $00CF, $0304, $0192
    DECLE   $018A, $022B, $0041, $0277, $015B, $0395, $03D1, $0082
    DECLE   $03CE, $00B6, $03BB, $02DA, $0000
_OW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_OY:
    DECLE   _OY.end - _OY - 1
    DECLE   $0310, $014C, $016E, $02A6, $03AF, $00CF, $0304, $0192
    DECLE   $03CA, $01A8, $007F, $0155, $02B4, $027F, $00E2, $036A
    DECLE   $031F, $035D, $0116, $01D5, $02F4, $025F, $033A, $038A
    DECLE   $014F, $01B5, $03D5, $0297, $02DA, $03F2, $0167, $0124
    DECLE   $03FB, $0001
_OY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_PA1:
    DECLE   _PA1.end - _PA1 - 1
    DECLE   $00F1, $0000
_PA1.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA2:
    DECLE   _PA2.end - _PA2 - 1
    DECLE   $00F4, $0000
_PA2.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA3:
    DECLE   _PA3.end - _PA3 - 1
    DECLE   $00F7, $0000
_PA3.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA4:
    DECLE   _PA4.end - _PA4 - 1
    DECLE   $00FF, $0000
_PA4.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA5:
    DECLE   _PA5.end - _PA5 - 1
    DECLE   $031D, $003F, $0000
_PA5.end:  ; 3 decles
;; ------------------------------------------------------------------------ ;;
_PP:
    DECLE   _PP.end - _PP - 1
    DECLE   $00FD, $0106, $0052, $0000, $022A, $03A5, $0277, $035F
    DECLE   $0184, $0000, $0055, $0391, $00EB, $00CF, $0000
_PP.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_RR1:
    DECLE   _RR1.end - _RR1 - 1
    DECLE   $0118, $01CD, $016C, $029E, $0171, $038E, $01E0, $0190
    DECLE   $0245, $0299, $01AA, $02E2, $01C7, $02DE, $0125, $00B5
    DECLE   $02C5, $028F, $024E, $035E, $01CB, $02EC, $0005, $0000
_RR1.end:  ; 24 decles
;; ------------------------------------------------------------------------ ;;
_RR2:
    DECLE   _RR2.end - _RR2 - 1
    DECLE   $0218, $03CC, $016C, $030C, $02C8, $0393, $02CD, $025E
    DECLE   $008A, $019D, $01AC, $02CB, $00BE, $0046, $017E, $01C2
    DECLE   $0174, $00A1, $01E5, $00E0, $010E, $0007, $0313, $0017
    DECLE   $0000
_RR2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SH:
    DECLE   _SH.end - _SH - 1
    DECLE   $0218, $0109, $0000, $007A, $0187, $02E0, $03F6, $0311
    DECLE   $0002, $0126, $0242, $0161, $03E9, $0219, $016C, $0300
    DECLE   $0013, $0045, $0124, $0005, $024C, $005C, $0182, $03C2
    DECLE   $0001
_SH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SS:
    DECLE   _SS.end - _SS - 1
    DECLE   $0218, $01CA, $0001, $0128, $001C, $0149, $01C6, $0000
_SS.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TH:
    DECLE   _TH.end - _TH - 1
    DECLE   $0019, $0349, $0000, $00C6, $0212, $01D8, $01CA, $0000
_TH.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TT1:
    DECLE   _TT1.end - _TT1 - 1
    DECLE   $00F6, $0046, $0142, $0100, $0042, $0088, $027E, $02EF
    DECLE   $01A4, $0200, $0049, $0290, $00FC, $00E8, $0000
_TT1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_TT2:
    DECLE   _TT2.end - _TT2 - 1
    DECLE   $00F5, $00C6, $01D2, $0100, $0335, $00E9, $0042, $027A
    DECLE   $02A4, $0000, $0062, $01D1, $014C, $03EA, $02EC, $01E0
    DECLE   $0007, $03A7, $0000
_TT2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_UH:
    DECLE   _UH.end - _UH - 1
    DECLE   $0018, $034E, $016E, $01FF, $0349, $00D2, $003C, $030C
    DECLE   $008B, $0005, $0000
_UH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_UW1:
    DECLE   _UW1.end - _UW1 - 1
    DECLE   $0318, $014C, $016F, $029E, $03BD, $03BD, $0271, $0212
    DECLE   $0325, $0291, $016A, $027B, $014A, $03B4, $0133, $0001
_UW1.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_UW2:
    DECLE   _UW2.end - _UW2 - 1
    DECLE   $0018, $034E, $016E, $02F6, $0107, $02C2, $006D, $0090
    DECLE   $03AC, $01A4, $01DC, $03AB, $0128, $0076, $03E6, $0119
    DECLE   $014F, $03A6, $03A5, $0020, $0090, $0001, $02EE, $00BB
    DECLE   $0000
_UW2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_VV:
    DECLE   _VV.end - _VV - 1
    DECLE   $0218, $030D, $016C, $010B, $010B, $0095, $034F, $03E4
    DECLE   $0108, $01B5, $01BE, $028B, $0160, $00AA, $03E4, $0106
    DECLE   $00EB, $02DE, $014C, $016E, $00F6, $0107, $00D2, $00CD
    DECLE   $0296, $00E4, $0006, $0000
_VV.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_WH:
    DECLE   _WH.end - _WH - 1
    DECLE   $0218, $00C9, $0000, $0084, $038E, $0147, $03A4, $0195
    DECLE   $0000, $012E, $0118, $0150, $02D1, $0232, $01B7, $03F1
    DECLE   $0237, $01C8, $03B1, $0227, $01AE, $0254, $0329, $032D
    DECLE   $01BF, $0169, $019A, $0307, $0181, $028D, $0000
_WH.end:  ; 31 decles
;; ------------------------------------------------------------------------ ;;
_WW:
    DECLE   _WW.end - _WW - 1
    DECLE   $0118, $034D, $016C, $00FA, $02C7, $0072, $03CC, $0109
    DECLE   $000B, $01AD, $019E, $016B, $0130, $0278, $01F8, $0314
    DECLE   $017E, $029E, $014D, $016D, $0205, $0147, $02E2, $001A
    DECLE   $010A, $026E, $0004, $0000
_WW.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_XR2:
    DECLE   _XR2.end - _XR2 - 1
    DECLE   $0318, $034C, $016E, $02A6, $03BB, $002F, $0290, $008E
    DECLE   $004B, $0392, $01DA, $024B, $013A, $01DA, $012F, $00B5
    DECLE   $02E5, $0297, $02DC, $0372, $014B, $016D, $0377, $00E7
    DECLE   $0376, $038A, $01CE, $026B, $02FA, $01AA, $011E, $0071
    DECLE   $00D5, $0297, $02BC, $02EA, $01C7, $02D7, $0135, $0155
    DECLE   $01DD, $0007, $0000
_XR2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_YR:
    DECLE   _YR.end - _YR - 1
    DECLE   $0318, $03CC, $016E, $0197, $00FD, $0130, $0270, $0094
    DECLE   $0328, $0291, $0168, $007E, $01CC, $02F5, $0125, $02B5
    DECLE   $00F4, $0298, $01DA, $03F6, $0153, $0126, $03B9, $00AB
    DECLE   $0293, $03DB, $0175, $01B9, $0001
_YR.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY1:
    DECLE   _YY1.end - _YY1 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0001, $0000
_YY1.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY2:
    DECLE   _YY2.end - _YY2 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0199, $01EE, $008B, $0161, $0232
    DECLE   $0004, $0318, $01A7, $0198, $0124, $03E0, $0001, $0001
    DECLE   $030F, $0027, $0000
_YY2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_ZH:
    DECLE   _ZH.end - _ZH - 1
    DECLE   $0310, $014D, $016E, $00C3, $03B9, $01BF, $0241, $0012
    DECLE   $0163, $00E1, $0000, $0080, $0084, $023F, $003F, $0000
_ZH.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_ZZ:
    DECLE   _ZZ.end - _ZZ - 1
    DECLE   $0218, $010D, $016F, $0225, $0351, $00B5, $02A0, $02EE
    DECLE   $00E9, $014D, $002C, $0360, $0008, $00EC, $004C, $0342
    DECLE   $03D4, $0156, $0052, $0131, $0008, $03B0, $01BE, $0172
    DECLE   $0000
_ZZ.end:  ; 25 decles

;;==========================================================================;;
;;                                                                          ;;
;;  Copyright information:                                                  ;;
;;                                                                          ;;
;;  The above allophone data was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is           ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY         ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.                                       ;;
;;                                                                          ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms        ;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.                                   ;;
;;                                                                          ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;                                                                          ;;
;;==========================================================================;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008                                     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  INTELLIVOICE DRIVER ROUTINES                                            ;;
;;  Written in 2002 by Joe Zbiciak <intvnut AT gmail.com>                   ;;
;;  http://spatula-city.org/~im14u2c/intv/                                  ;;
;; ======================================================================== ;;

;; ======================================================================== ;;
;;  GLOBAL VARIABLES USED BY THESE ROUTINES                                 ;;
;;                                                                          ;;
;;  Note that some of these routines may use one or more global variables.  ;;
;;  If you use these routines, you will need to allocate the appropriate    ;;
;;  space in either 16-bit or 8-bit memory as appropriate.  Each global     ;;
;;  variable is listed with the routines which use it and the required      ;;
;;  memory width.                                                           ;;
;;                                                                          ;;
;;  Example declarations for these routines are shown below, commented out. ;;
;;  You should uncomment these and add them to your program to make use of  ;;
;;  the routine that needs them.  Make sure to assign these variables to    ;;
;;  locations that aren't used for anything else.                           ;;
;; ======================================================================== ;;

                        ; Used by       Req'd Width     Description
                        ;-----------------------------------------------------
;IV.QH      EQU $110    ; IV_xxx        8-bit           Voice queue head
;IV.QT      EQU $111    ; IV_xxx        8-bit           Voice queue tail
;IV.Q       EQU $112    ; IV_xxx        8-bit           Voice queue  (8 bytes)
;IV.FLEN    EQU $11A    ; IV_xxx        8-bit           Length of FIFO data
;IV.FPTR    EQU $320    ; IV_xxx        16-bit          Current FIFO ptr.
;IV.PPTR    EQU $321    ; IV_xxx        16-bit          Current Phrase ptr.

;; ======================================================================== ;;
;;  MEMORY USAGE                                                            ;;
;;                                                                          ;;
;;  These routines implement a queue of "pending phrases" that will be      ;;
;;  played by the Intellivoice.  The user calls IV_PLAY to enqueue a        ;;
;;  phrase number.  Phrase numbers indicate either a RESROM sample or       ;;
;;  a compiled in phrase to be spoken.                                      ;;
;;                                                                          ;;
;;  The user must compose an "IV_PHRASE_TBL", which is composed of          ;;
;;  pointers to phrases to be spoken.  Phrases are strings of pointers      ;;
;;  and RESROM triggers, terminated by a NUL.                               ;;
;;                                                                          ;;
;;  Phrase numbers 1 through 42 are RESROM samples.  Phrase numbers         ;;
;;  43 through 255 index into the IV_PHRASE_TBL.                            ;;
;;                                                                          ;;
;;  SPECIAL NOTES                                                           ;;
;;                                                                          ;;
;;  Bit 7 of IV.QH and IV.QT is used to denote whether the Intellivoice     ;;
;;  is present.  If Intellivoice is present, this bit is clear.             ;;
;;                                                                          ;;
;;  Bit 6 of IV.QT is used to denote that we still need to do an ALD $00    ;;
;;  for FIFO'd voice data.                                                  ;;
;; ======================================================================== ;;
            

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_INIT     Initialize the Intellivoice                             ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_INIT                                                      ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0      0 if Intellivoice found, -1 if not.                         ;;
;;                                                                          ;;
;;  DESCRIPTION                                                             ;;
;;      Resets Intellivoice, determines if it is actually there, and        ;;
;;      then initializes the IV structure.                                  ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;

IV_INIT     PROC
            MVII    #$0400, R0          ;
            MVO     R0,     $0081       ; Reset the Intellivoice

            MVI     $0081,  R0          ; \
            RLC     R0,     2           ;  |-- See if we detect Intellivoice
            BOV     @@no_ivoice         ; /    once we've reset it.

            CLRR    R0                  ; 
            MVO     R0,     IV.FPTR     ; No data for FIFO
            MVO     R0,     IV.PPTR     ; No phrase being spoken
            MVO     R0,     IV.QH       ; Clear our queue
            MVO     R0,     IV.QT       ; Clear our queue
            JR      R5                  ; Done!

@@no_ivoice:
            CLRR    R0
            MVO     R0,     IV.FPTR     ; No data for FIFO
            MVO     R0,     IV.PPTR     ; No phrase being spoken
            DECR    R0
            MVO     R0,     IV.QH       ; Set queue to -1 ("No Intellivoice")
            MVO     R0,     IV.QT       ; Set queue to -1 ("No Intellivoice")
            JR      R5                  ; Done!
            ENDP

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_ISR      Interrupt service routine to feed Intellivoice          ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_ISR                                                       ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0, R1, R4 trashed.                                                 ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      Call this from your main interrupt service routine.                 ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_ISR      PROC
            ;; ------------------------------------------------------------ ;;
            ;;  Check for Intellivoice.  Leave if none present.             ;;
            ;; ------------------------------------------------------------ ;;
            MVI     IV.QT,  R1          ; Get queue tail
            SWAP    R1,     2
            BPL     @@ok                ; Bit 7 set? If yes: No Intellivoice
@@ald_busy:
@@leave     JR      R5                  ; Exit if no Intellivoice.

     
            ;; ------------------------------------------------------------ ;;
            ;;  Check to see if we pump samples into the FIFO.
            ;; ------------------------------------------------------------ ;;
@@ok:       MVI     IV.FPTR, R4         ; Get FIFO data pointer
            TSTR    R4                  ; is it zero?
            BEQ     @@no_fifodata       ; Yes:  No data for FIFO.
@@fifo_fill:
            MVI     $0081,  R0          ; Read speech FIFO ready bit
            SLLC    R0,     1           ; 
            BC      @@fifo_busy     

            MVI@    R4,     R0          ; Get next word
            MVO     R0,     $0081       ; write it to the FIFO

            MVI     IV.FLEN, R0         ;\
            DECR    R0                  ; |-- Decrement our FIFO'd data length
            MVO     R0,     IV.FLEN     ;/
            BEQ     @@last_fifo         ; If zero, we're done w/ FIFO
            MVO     R4,     IV.FPTR     ; Otherwise, save new pointer
            B       @@fifo_fill         ; ...and keep trying to load FIFO

@@last_fifo MVO     R0,     IV.FPTR     ; done with FIFO loading.
                                        ; fall into ALD processing.


            ;; ------------------------------------------------------------ ;;
            ;;  Try to do an Address Load.  We do this in two settings:     ;;
            ;;   -- We have no FIFO data to load.                           ;;
            ;;   -- We've loaded as much FIFO data as we can, but we        ;;
            ;;      might have an address load command to send for it.      ;;
            ;; ------------------------------------------------------------ ;;
@@fifo_busy:
@@no_fifodata:
            MVI     $0080,  R0          ; Read LRQ bit from ALD register
            SLLC    R0,     1
            BNC     @@ald_busy          ; LRQ is low, meaning we can't ALD.
                                        ; So, leave.

            ;; ------------------------------------------------------------ ;;
            ;;  We can do an address load (ALD) on the SP0256.  Give FIFO   ;;
            ;;  driven ALDs priority, since we already started the FIFO     ;;
            ;;  load.  The "need ALD" bit is stored in bit 6 of IV.QT.      ;;
            ;; ------------------------------------------------------------ ;;
            ANDI    #$40,   R1          ; Is "Need FIFO ALD" bit set?
            BEQ     @@no_fifo_ald
            XOR     IV.QT,  R1          ;\__ Clear the "Need FIFO ALD" bit.
            MVO     R1,     IV.QT       ;/
            CLRR    R1
            MVO     R1,     $80         ; Load a 0 into ALD (trigger FIFO rd.)
            JR      R5                  ; done!

            ;; ------------------------------------------------------------ ;;
            ;;  We don't need to ALD on behalf of the FIFO.  So, we grab    ;;
            ;;  the next thing off our phrase list.                         ;;
            ;; ------------------------------------------------------------ ;;
@@no_fifo_ald:
            MVI     IV.PPTR, R4         ; Get phrase pointer.
            TSTR    R4                  ; Is it zero?
            BEQ     @@next_phrase       ; Yes:  Get next phrase from queue.

            MVI@    R4,     R0
            TSTR    R0                  ; Is it end of phrase?
            BNEQ    @@process_phrase    ; !=0:  Go do it.

            MVO     R0,     IV.PPTR     ; 
@@next_phrase:
            MVI     IV.QT,  R1          ; reload queue tail (was trashed above)
            MOVR    R1,     R0          ; copy QT to R0 so we can increment it
            ANDI    #$7,    R1          ; Mask away flags in queue head
            CMP     IV.QH,  R1          ; Is it same as queue tail?
            BEQ     @@leave             ; Yes:  No more speech for now.

            INCR    R0
            ANDI    #$F7,   R0          ; mask away the possible 'carry'
            MVO     R0,     IV.QT       ; save updated queue tail

            ADDI    #IV.Q,  R1          ; Index into queue
            MVI@    R1,     R4          ; get next value from queue
            CMPI    #43,    R4          ; Is it a RESROM or Phrase?
            BNC     @@play_resrom_r4
@@new_phrase:
;            ADDI    #IV_PHRASE_TBL - 43, R4 ; Index into phrase table
;            MVI@    R4,     R4          ; Read from phrase table
            MVO     R4,     IV.PPTR
            JR      R5                  ; we'll get to this phrase next time.

@@play_resrom_r4:
            MVO     R4,     $0080       ; Just ALD it
            JR      R5                  ; and leave.

            ;; ------------------------------------------------------------ ;;
            ;;  We're in the middle of a phrase, so continue interpreting.  ;;
            ;; ------------------------------------------------------------ ;;
@@process_phrase:
            
            MVO     R4,     IV.PPTR     ; save new phrase pointer
            CMPI    #43,    R0          ; Is it a RESROM cue?
            BC      @@play_fifo         ; Just ALD it and leave.
@@play_resrom_r0
            MVO     R0,     $0080       ; Just ALD it
            JR      R5                  ; and leave.
@@play_fifo:
            MVI     IV.FPTR,R1          ; Make sure not to stomp existing FIFO
            TSTR    R1                  ; data.
            BEQ     @@new_fifo_ok
            DECR    R4                  ; Oops, FIFO data still playing,
            MVO     R4,     IV.PPTR     ; so rewind.
            JR      R5                  ; and leave.

@@new_fifo_ok:
            MOVR    R0,     R4          ;
            MVI@    R4,     R0          ; Get chunk length
            MVO     R0,     IV.FLEN     ; Init FIFO chunk length
            MVO     R4,     IV.FPTR     ; Init FIFO pointer
            MVI     IV.QT,  R0          ;\
            XORI    #$40,   R0          ; |- Set "Need ALD" bit in QT
            MVO     R0,     IV.QT       ;/

  IF 1      ; debug code                ;\
            ANDI    #$40,   R0          ; |   Debug code:  We should only
            BNEQ    @@qtok              ; |-- be here if "Need FIFO ALD" 
            HLT     ;BUG!!              ; |   was already clear.         
@@qtok                                  ;/    
  ENDI
            JR      R5                  ; leave.

            ENDP


;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_PLAY     Play a voice sample sequence.                           ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY                                                      ;;
;;      R5      Invocation record, followed by return address.              ;;
;;                  1 DECLE    Phrase number to play.                       ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY.1                                                    ;;
;;      R0      Address of phrase to play.                                  ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0, R1  trashed                                                     ;;
;;      Z==0    if item not successfully queued.                            ;;
;;      Z==1    if successfully queued.                                     ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This code will drop phrases if the queue is full.                   ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index        ;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the         ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;                                                                          ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_PLAY     PROC
            MVI@    R5,     R0

@@1:        ; alternate entry point
            MVI     IV.QT,  R1          ; Get queue tail
            SWAP    R1,     2           ;\___ Leave if "no Intellivoice"
            BMI     @@leave             ;/    bit it set.
@@ok:       
            DECR    R1                  ;\
            ANDI    #$7,    R1          ; |-- See if we still have room
            CMP     IV.QH,  R1          ;/
            BEQ     @@leave             ; Leave if we're full

@@2:        MVI     IV.QH,  R1          ; Get our queue head pointer
            PSHR    R1                  ;\
            INCR    R1                  ; |
            ANDI    #$F7,   R1          ; |-- Increment it, removing
            MVO     R1,     IV.QH       ; |   carry but preserving flags.
            PULR    R1                  ;/

            ADDI    #IV.Q,  R1          ;\__ Store phrase to queue
            MVO@    R0,     R1          ;/

@@leave:    JR      R5                  ; Leave.
            ENDP

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_PLAYW    Play a voice sample sequence.  Wait for queue room.     ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY                                                      ;;
;;      R5      Invocation record, followed by return address.              ;;
;;                  1 DECLE    Phrase number to play.                       ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY.1                                                    ;;
;;      R0      Address of phrase to play.                                  ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0, R1  trashed                                                     ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This code will wait for a queue slot to open if queue is full.      ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index        ;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the         ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;                                                                          ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_PLAYW    PROC
            MVI@    R5,     R0

@@1:        ; alternate entry point
            MVI     IV.QT,  R1          ; Get queue tail
            SWAP    R1,     2           ;\___ Leave if "no Intellivoice"
            BMI     IV_PLAY.leave       ;/    bit it set.
@@ok:       
            DECR    R1                  ;\
            ANDI    #$7,    R1          ; |-- See if we still have room
            CMP     IV.QH,  R1          ;/
            BEQ     @@1                 ; wait for room
            B       IV_PLAY.2

            ENDP

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_WAIT     Wait for voice queue to empty.                          ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_WAIT                                                      ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0      trashed.                                                    ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This waits until the Intellivoice is nearly completely quiescent.   ;;
;;      Some voice data may still be spoken from the last triggered         ;;
;;      phrase.  To truly wait for *that* to be spoken, speak a 'pause'     ;;
;;      (eg. RESROM.pa1) and then call IV_WAIT.                             ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_WAIT     PROC
            MVI     IV.QH,  R0
            SWAP    R0                  ;\___ test bit 7, leave if set.
            SWAP    R0                  ;/    (SWAP2 corrupts upper byte.)
            BMI     @@leave

            ; Wait for queue to drain.
@@q_loop:   CMP     IV.QT,  R0
            BNEQ    @@q_loop

            ; Wait for FIFO and LRQ to say ready.
@@s_loop:   MVI     $81,    R0          ; Read FIFO status.  0 == ready.
            COMR    R0
            AND     $80,    R0          ; Merge w/ ALD status.  1 == ready
            TSTR    R0
            BPL     @@s_loop            ; if bit 15 == 0, not ready.
            
@@leave:    JR      R5
            ENDP

;; ======================================================================== ;;
;;  End of File:  ivoice.asm                                                ;;
;; ======================================================================== ;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008                                     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_SAYNUM16 Say a 16-bit unsigned number using RESROM digits        ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      16-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_INIT                                                      ;;
;;      R0      Number to "speak"                                           ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;                                                                          ;;
;;  DESCRIPTION                                                             ;;
;;      "Says" a 16-bit number using IV_PLAYW to queue up the phrase.       ;;
;;      Because the number may be built from several segments, it could     ;;
;;      easily eat up the queue.  I believe the longest number will take    ;;
;;      7 queue entries -- that is, fill the queue.  Thus, this code        ;;
;;      could block, waiting for slots in the queue.                        ;;
;; ======================================================================== ;;

IV_SAYNUM16 PROC
            PSHR    R5

            TSTR    R0
            BEQ     @@zero          ; Special case:  Just say "zero"

            ;; ------------------------------------------------------------ ;;
            ;;  First, try to pull off 'thousands'.  We call ourselves      ;;
            ;;  recursively to play the the number of thousands.            ;;
            ;; ------------------------------------------------------------ ;;
            CLRR    R1
@@thloop:   INCR    R1
            SUBI    #1000,  R0
            BC      @@thloop

            ADDI    #1000,  R0
            PSHR    R0
            DECR    R1
            BEQ     @@no_thousand

            CALL    IV_SAYNUM16.recurse

            CALL    IV_PLAYW
            DECLE   36  ; THOUSAND
            
@@no_thousand
            PULR    R1

            ;; ------------------------------------------------------------ ;;
            ;;  Now try to play hundreds.                                   ;;
            ;; ------------------------------------------------------------ ;;
            MVII    #7-1, R0    ; ZERO
            CMPI    #100,   R1
            BNC     @@no_hundred

@@hloop:    INCR    R0
            SUBI    #100,   R1
            BC      @@hloop
            ADDI    #100,   R1

            PSHR    R1

            CALL    IV_PLAYW.1

            CALL    IV_PLAYW
            DECLE   35  ; HUNDRED

            PULR    R1
            B       @@notrecurse    ; skip "PSHR R5"
@@recurse:  PSHR    R5              ; recursive entry point for 'thousand'

@@no_hundred:
@@notrecurse:
            MOVR    R1,     R0
            BEQ     @@leave

            SUBI    #20,    R1
            BNC     @@teens

            MVII    #27-1, R0   ; TWENTY
@@tyloop    INCR    R0
            SUBI    #10,    R1
            BC      @@tyloop
            ADDI    #10,    R1

            PSHR    R1
            CALL    IV_PLAYW.1

            PULR    R0
            TSTR    R0
            BEQ     @@leave

@@teens:
@@zero:     ADDI    #7, R0  ; ZERO

            CALL    IV_PLAYW.1

@@leave     PULR    PC
            ENDP

;; ======================================================================== ;;
;;  End of File:  saynum16.asm                                              ;;
;; ======================================================================== ;;

    ENDI

        IF DEFINED intybasic_flash

;; ======================================================================== ;;
;;  JLP "Save Game" support                                                 ;;
;; ======================================================================== ;;
JF.first    EQU     $8023
JF.last     EQU     $8024
JF.addr     EQU     $8025
JF.row      EQU     $8026
                   
JF.wrcmd    EQU     $802D
JF.rdcmd    EQU     $802E
JF.ercmd    EQU     $802F
JF.wrkey    EQU     $C0DE
JF.rdkey    EQU     $DEC0
JF.erkey    EQU     $BEEF

JF.write:   DECLE   JF.wrcmd,   JF.wrkey    ; Copy JLP RAM to flash row  
JF.read:    DECLE   JF.rdcmd,   JF.rdkey    ; Copy flash row to JLP RAM  
JF.erase:   DECLE   JF.ercmd,   JF.erkey    ; Erase flash sector 

;; ======================================================================== ;;
;;  JF.INIT         Copy JLP save-game support routine to System RAM        ;;
;; ======================================================================== ;;
JF.INIT     PROC
            PSHR    R5            
            MVII    #@@__code,  R5
            MVII    #JF.SYSRAM, R4
            REPEAT  5       
            MVI@    R5,         R0      ; \_ Copy code fragment to System RAM
            MVO@    R0,         R4      ; /
            ENDR
            PULR    PC

            ;; === start of code that will run from RAM
@@__code:   MVO@    R0,         R1      ; JF.SYSRAM + 0: initiate command
            ADD@    R1,         PC      ; JF.SYSRAM + 1: Wait for JLP to return
            JR      R5                  ; JF.SYSRAM + 2:
            MVO@    R2,         R2      ; JF.SYSRAM + 3: \__ simple ISR
            JR      R5                  ; JF.SYSRAM + 4: /
            ;; === end of code that will run from RAM
            ENDP

;; ======================================================================== ;;
;;  JF.CMD          Issue a JLP Flash command                               ;;
;;                                                                          ;;
;;  INPUT                                                                   ;;
;;      R0  Slot number to operate on                                       ;;
;;      R1  Address to copy to/from in JLP RAM                              ;;
;;      @R5 Command to invoke:                                              ;;
;;                                                                          ;;
;;              JF.write -- Copy JLP RAM to Flash                           ;;
;;              JF.read  -- Copy Flash to JLP RAM                           ;;
;;              JF.erase -- Erase flash sector                              ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      R0 - R4 not modified.  (Saved and restored across call)             ;;
;;      JLP command executed                                                ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This code requires two short routines in the console's System RAM.  ;;
;;      It also requires that the system stack reside in System RAM.        ;;
;;      Because an interrupt may occur during the code's execution, there   ;;
;;      must be sufficient stack space to service the interrupt (8 words).  ;;
;;                                                                          ;;
;;      The code also relies on the fact that the EXEC ISR dispatch does    ;;
;;      not modify R2.  This allows us to initialize R2 for the ISR ahead   ;;
;;      of time, rather than in the ISR.                                    ;;
;; ======================================================================== ;;
JF.CMD      PROC

            MVO     R4,         JF.SV.R4    ; \
            MVII    #JF.SV.R0,  R4          ;  |
            MVO@    R0,         R4          ;  |- Save registers, but not on
            MVO@    R1,         R4          ;  |  the stack.  (limit stack use)
            MVO@    R2,         R4          ; /

            MVI@    R5,         R4          ; Get command to invoke

            MVO     R5,         JF.SV.R5    ; save return address

            DIS
            MVO     R1,         JF.addr     ; \_ Save SG arguments in JLP
            MVO     R0,         JF.row      ; /
                                          
            MVI@    R4,         R1          ; Get command address
            MVI@    R4,         R0          ; Get unlock word
                                          
            MVII    #$100,      R4          ; \
            SDBD                            ;  |_ Save old ISR in save area
            MVI@    R4,         R2          ;  |
            MVO     R2,         JF.SV.ISR   ; /
                                          
            MVII    #JF.SYSRAM + 3, R2      ; \
            MVO     R2,         $100        ;  |_ Set up new ISR in RAM
            SWAP    R2                      ;  |
            MVO     R2,         $101        ; / 
                                          
            MVII    #$20,       R2          ; Address of STIC handshake
            JSRE    R5,  JF.SYSRAM          ; Invoke the command
                                          
            MVI     JF.SV.ISR,  R2          ; \
            MVO     R2,         $100        ;  |_ Restore old ISR 
            SWAP    R2                      ;  |
            MVO     R2,         $101        ; /
                                          
            MVII    #JF.SV.R0,  R5          ; \
            MVI@    R5,         R0          ;  |
            MVI@    R5,         R1          ;  |- Restore registers
            MVI@    R5,         R2          ;  |
            MVI@    R5,         R4          ; /
            MVI@    R5,         PC          ; Return

            ENDP


        ENDI

	IF DEFINED intybasic_fastmult

; Quarter Square Multiplication
; Assembly code by Joe Zbiciak, 2015
; Released to public domain.

QSQR8_TBL:  PROC
            DECLE   $3F80, $3F01, $3E82, $3E04, $3D86, $3D09, $3C8C, $3C10
            DECLE   $3B94, $3B19, $3A9E, $3A24, $39AA, $3931, $38B8, $3840
            DECLE   $37C8, $3751, $36DA, $3664, $35EE, $3579, $3504, $3490
            DECLE   $341C, $33A9, $3336, $32C4, $3252, $31E1, $3170, $3100
            DECLE   $3090, $3021, $2FB2, $2F44, $2ED6, $2E69, $2DFC, $2D90
            DECLE   $2D24, $2CB9, $2C4E, $2BE4, $2B7A, $2B11, $2AA8, $2A40
            DECLE   $29D8, $2971, $290A, $28A4, $283E, $27D9, $2774, $2710
            DECLE   $26AC, $2649, $25E6, $2584, $2522, $24C1, $2460, $2400
            DECLE   $23A0, $2341, $22E2, $2284, $2226, $21C9, $216C, $2110
            DECLE   $20B4, $2059, $1FFE, $1FA4, $1F4A, $1EF1, $1E98, $1E40
            DECLE   $1DE8, $1D91, $1D3A, $1CE4, $1C8E, $1C39, $1BE4, $1B90
            DECLE   $1B3C, $1AE9, $1A96, $1A44, $19F2, $19A1, $1950, $1900
            DECLE   $18B0, $1861, $1812, $17C4, $1776, $1729, $16DC, $1690
            DECLE   $1644, $15F9, $15AE, $1564, $151A, $14D1, $1488, $1440
            DECLE   $13F8, $13B1, $136A, $1324, $12DE, $1299, $1254, $1210
            DECLE   $11CC, $1189, $1146, $1104, $10C2, $1081, $1040, $1000
            DECLE   $0FC0, $0F81, $0F42, $0F04, $0EC6, $0E89, $0E4C, $0E10
            DECLE   $0DD4, $0D99, $0D5E, $0D24, $0CEA, $0CB1, $0C78, $0C40
            DECLE   $0C08, $0BD1, $0B9A, $0B64, $0B2E, $0AF9, $0AC4, $0A90
            DECLE   $0A5C, $0A29, $09F6, $09C4, $0992, $0961, $0930, $0900
            DECLE   $08D0, $08A1, $0872, $0844, $0816, $07E9, $07BC, $0790
            DECLE   $0764, $0739, $070E, $06E4, $06BA, $0691, $0668, $0640
            DECLE   $0618, $05F1, $05CA, $05A4, $057E, $0559, $0534, $0510
            DECLE   $04EC, $04C9, $04A6, $0484, $0462, $0441, $0420, $0400
            DECLE   $03E0, $03C1, $03A2, $0384, $0366, $0349, $032C, $0310
            DECLE   $02F4, $02D9, $02BE, $02A4, $028A, $0271, $0258, $0240
            DECLE   $0228, $0211, $01FA, $01E4, $01CE, $01B9, $01A4, $0190
            DECLE   $017C, $0169, $0156, $0144, $0132, $0121, $0110, $0100
            DECLE   $00F0, $00E1, $00D2, $00C4, $00B6, $00A9, $009C, $0090
            DECLE   $0084, $0079, $006E, $0064, $005A, $0051, $0048, $0040
            DECLE   $0038, $0031, $002A, $0024, $001E, $0019, $0014, $0010
            DECLE   $000C, $0009, $0006, $0004, $0002, $0001, $0000
@@mid:
            DECLE   $0000, $0000, $0001, $0002, $0004, $0006, $0009, $000C
            DECLE   $0010, $0014, $0019, $001E, $0024, $002A, $0031, $0038
            DECLE   $0040, $0048, $0051, $005A, $0064, $006E, $0079, $0084
            DECLE   $0090, $009C, $00A9, $00B6, $00C4, $00D2, $00E1, $00F0
            DECLE   $0100, $0110, $0121, $0132, $0144, $0156, $0169, $017C
            DECLE   $0190, $01A4, $01B9, $01CE, $01E4, $01FA, $0211, $0228
            DECLE   $0240, $0258, $0271, $028A, $02A4, $02BE, $02D9, $02F4
            DECLE   $0310, $032C, $0349, $0366, $0384, $03A2, $03C1, $03E0
            DECLE   $0400, $0420, $0441, $0462, $0484, $04A6, $04C9, $04EC
            DECLE   $0510, $0534, $0559, $057E, $05A4, $05CA, $05F1, $0618
            DECLE   $0640, $0668, $0691, $06BA, $06E4, $070E, $0739, $0764
            DECLE   $0790, $07BC, $07E9, $0816, $0844, $0872, $08A1, $08D0
            DECLE   $0900, $0930, $0961, $0992, $09C4, $09F6, $0A29, $0A5C
            DECLE   $0A90, $0AC4, $0AF9, $0B2E, $0B64, $0B9A, $0BD1, $0C08
            DECLE   $0C40, $0C78, $0CB1, $0CEA, $0D24, $0D5E, $0D99, $0DD4
            DECLE   $0E10, $0E4C, $0E89, $0EC6, $0F04, $0F42, $0F81, $0FC0
            DECLE   $1000, $1040, $1081, $10C2, $1104, $1146, $1189, $11CC
            DECLE   $1210, $1254, $1299, $12DE, $1324, $136A, $13B1, $13F8
            DECLE   $1440, $1488, $14D1, $151A, $1564, $15AE, $15F9, $1644
            DECLE   $1690, $16DC, $1729, $1776, $17C4, $1812, $1861, $18B0
            DECLE   $1900, $1950, $19A1, $19F2, $1A44, $1A96, $1AE9, $1B3C
            DECLE   $1B90, $1BE4, $1C39, $1C8E, $1CE4, $1D3A, $1D91, $1DE8
            DECLE   $1E40, $1E98, $1EF1, $1F4A, $1FA4, $1FFE, $2059, $20B4
            DECLE   $2110, $216C, $21C9, $2226, $2284, $22E2, $2341, $23A0
            DECLE   $2400, $2460, $24C1, $2522, $2584, $25E6, $2649, $26AC
            DECLE   $2710, $2774, $27D9, $283E, $28A4, $290A, $2971, $29D8
            DECLE   $2A40, $2AA8, $2B11, $2B7A, $2BE4, $2C4E, $2CB9, $2D24
            DECLE   $2D90, $2DFC, $2E69, $2ED6, $2F44, $2FB2, $3021, $3090
            DECLE   $3100, $3170, $31E1, $3252, $32C4, $3336, $33A9, $341C
            DECLE   $3490, $3504, $3579, $35EE, $3664, $36DA, $3751, $37C8
            DECLE   $3840, $38B8, $3931, $39AA, $3A24, $3A9E, $3B19, $3B94
            DECLE   $3C10, $3C8C, $3D09, $3D86, $3E04, $3E82, $3F01, $3F80
            DECLE   $4000, $4080, $4101, $4182, $4204, $4286, $4309, $438C
            DECLE   $4410, $4494, $4519, $459E, $4624, $46AA, $4731, $47B8
            DECLE   $4840, $48C8, $4951, $49DA, $4A64, $4AEE, $4B79, $4C04
            DECLE   $4C90, $4D1C, $4DA9, $4E36, $4EC4, $4F52, $4FE1, $5070
            DECLE   $5100, $5190, $5221, $52B2, $5344, $53D6, $5469, $54FC
            DECLE   $5590, $5624, $56B9, $574E, $57E4, $587A, $5911, $59A8
            DECLE   $5A40, $5AD8, $5B71, $5C0A, $5CA4, $5D3E, $5DD9, $5E74
            DECLE   $5F10, $5FAC, $6049, $60E6, $6184, $6222, $62C1, $6360
            DECLE   $6400, $64A0, $6541, $65E2, $6684, $6726, $67C9, $686C
            DECLE   $6910, $69B4, $6A59, $6AFE, $6BA4, $6C4A, $6CF1, $6D98
            DECLE   $6E40, $6EE8, $6F91, $703A, $70E4, $718E, $7239, $72E4
            DECLE   $7390, $743C, $74E9, $7596, $7644, $76F2, $77A1, $7850
            DECLE   $7900, $79B0, $7A61, $7B12, $7BC4, $7C76, $7D29, $7DDC
            DECLE   $7E90, $7F44, $7FF9, $80AE, $8164, $821A, $82D1, $8388
            DECLE   $8440, $84F8, $85B1, $866A, $8724, $87DE, $8899, $8954
            DECLE   $8A10, $8ACC, $8B89, $8C46, $8D04, $8DC2, $8E81, $8F40
            DECLE   $9000, $90C0, $9181, $9242, $9304, $93C6, $9489, $954C
            DECLE   $9610, $96D4, $9799, $985E, $9924, $99EA, $9AB1, $9B78
            DECLE   $9C40, $9D08, $9DD1, $9E9A, $9F64, $A02E, $A0F9, $A1C4
            DECLE   $A290, $A35C, $A429, $A4F6, $A5C4, $A692, $A761, $A830
            DECLE   $A900, $A9D0, $AAA1, $AB72, $AC44, $AD16, $ADE9, $AEBC
            DECLE   $AF90, $B064, $B139, $B20E, $B2E4, $B3BA, $B491, $B568
            DECLE   $B640, $B718, $B7F1, $B8CA, $B9A4, $BA7E, $BB59, $BC34
            DECLE   $BD10, $BDEC, $BEC9, $BFA6, $C084, $C162, $C241, $C320
            DECLE   $C400, $C4E0, $C5C1, $C6A2, $C784, $C866, $C949, $CA2C
            DECLE   $CB10, $CBF4, $CCD9, $CDBE, $CEA4, $CF8A, $D071, $D158
            DECLE   $D240, $D328, $D411, $D4FA, $D5E4, $D6CE, $D7B9, $D8A4
            DECLE   $D990, $DA7C, $DB69, $DC56, $DD44, $DE32, $DF21, $E010
            DECLE   $E100, $E1F0, $E2E1, $E3D2, $E4C4, $E5B6, $E6A9, $E79C
            DECLE   $E890, $E984, $EA79, $EB6E, $EC64, $ED5A, $EE51, $EF48
            DECLE   $F040, $F138, $F231, $F32A, $F424, $F51E, $F619, $F714
            DECLE   $F810, $F90C, $FA09, $FB06, $FC04, $FD02, $FE01
            ENDP

; R0 = R0 * R1, where R0 and R1 are unsigned 8-bit values
; Destroys R1, R4
qs_mpy8:    PROC
            MOVR    R0,             R4      ;   6
            ADDI    #QSQR8_TBL.mid, R1      ;   8
            ADDR    R1,             R4      ;   6   a + b
            SUBR    R0,             R1      ;   6   a - b
@@ok:       MVI@    R4,             R0      ;   8
            SUB@    R1,             R0      ;   8
            JR      R5                      ;   7
                                            ;----
                                            ;  49
            ENDP
            

; R1 = R0 * R1, where R0 and R1 are 16-bit values
; destroys R0, R2, R3, R4, R5
qs_mpy16:   PROC
            PSHR    R5                  ;   9
                                   
            ; Unpack lo/hi
            MOVR    R0,         R2      ;   6   
            ANDI    #$FF,       R0      ;   8   R0 is lo(a)
            XORR    R0,         R2      ;   6   
            SWAP    R2                  ;   6   R2 is hi(a)

            MOVR    R1,         R3      ;   6   R3 is orig 16-bit b
            ANDI    #$FF,       R1      ;   8   R1 is lo(b)
            MOVR    R1,         R5      ;   6   R5 is lo(b)
            XORR    R1,         R3      ;   6   
            SWAP    R3                  ;   6   R3 is hi(b)
                                        ;----
                                        ;  67
                                        
            ; lo * lo                   
            MOVR    R0,         R4      ;   6   R4 is lo(a)
            ADDI    #QSQR8_TBL.mid, R1  ;   8
            ADDR    R1,         R4      ;   6   R4 = lo(a) + lo(b)
            SUBR    R0,         R1      ;   6   R1 = lo(a) - lo(b)
                                        
@@pos_ll:   MVI@    R4,         R4      ;   8   R4 = qstbl[lo(a)+lo(b)]
            SUB@    R1,         R4      ;   8   R4 = lo(a)*lo(b)
                                        ;----
                                        ;  42
                                        ;  67 (carried forward)
                                        ;----
                                        ; 109
                                       
            ; lo * hi                  
            MOVR    R0,         R1      ;   6   R0 = R1 = lo(a)
            ADDI    #QSQR8_TBL.mid, R3  ;   8
            ADDR    R3,         R1      ;   6   R1 = hi(b) + lo(a)
            SUBR    R0,         R3      ;   6   R3 = hi(b) - lo(a)
                                       
@@pos_lh:   MVI@    R1,         R1      ;   8   R1 = qstbl[hi(b)-lo(a)]
            SUB@    R3,         R1      ;   8   R1 = lo(a)*hi(b)
                                        ;----
                                        ;  42
                                        ; 109 (carried forward)
                                        ;----
                                        ; 151
                                       
            ; hi * lo                  
            MOVR    R5,         R0      ;   6   R5 = R0 = lo(b)
            ADDI    #QSQR8_TBL.mid, R2  ;   8
            ADDR    R2,         R5      ;   6   R3 = hi(a) + lo(b)
            SUBR    R0,         R2      ;   6   R2 = hi(a) - lo(b)
                                       
@@pos_hl:   ADD@    R5,         R1      ;   8   \_ R1 = lo(a)*hi(b)+hi(a)*lo(b)
            SUB@    R2,         R1      ;   8   /
                                        ;----
                                        ;  42
                                        ; 151 (carried forward)
                                        ;----
                                        ; 193
                                       
            SWAP    R1                  ;   6   \_ shift upper product left 8
            ANDI    #$FF00,     R1      ;   8   /
            ADDR    R4,         R1      ;   6   final product
            PULR    PC                  ;  12
                                        ;----
                                        ;  32
                                        ; 193 (carried forward)
                                        ;----
                                        ; 225
            ENDP

	ENDI

	IF DEFINED intybasic_fastdiv

; Fast unsigned division/remainder
; Assembly code by Oscar Toledo G. Jul/10/2015
; Released to public domain.

	; Ultrafast unsigned division/remainder operation
	; Entry: R0 = Dividend
	;        R1 = Divisor
	; Output: R0 = Quotient
	;         R2 = Remainder
	; Worst case: 6 + 6 + 9 + 496 = 517 cycles
	; Best case: 6 + (6 + 7) * 16 = 214 cycles

uf_udiv16:	PROC
	CLRR R2		; 6
	SLLC R0,1	; 6
	BC @@1		; 7/9
	SLLC R0,1	; 6
	BC @@2		; 7/9
	SLLC R0,1	; 6
	BC @@3		; 7/9
	SLLC R0,1	; 6
	BC @@4		; 7/9
	SLLC R0,1	; 6
	BC @@5		; 7/9
	SLLC R0,1	; 6
	BC @@6		; 7/9
	SLLC R0,1	; 6
	BC @@7		; 7/9
	SLLC R0,1	; 6
	BC @@8		; 7/9
	SLLC R0,1	; 6
	BC @@9		; 7/9
	SLLC R0,1	; 6
	BC @@10		; 7/9
	SLLC R0,1	; 6
	BC @@11		; 7/9
	SLLC R0,1	; 6
	BC @@12		; 7/9
	SLLC R0,1	; 6
	BC @@13		; 7/9
	SLLC R0,1	; 6
	BC @@14		; 7/9
	SLLC R0,1	; 6
	BC @@15		; 7/9
	SLLC R0,1	; 6
	BC @@16		; 7/9
	JR R5

@@1:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@2:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@3:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@4:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@5:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@6:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@7:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@8:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@9:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@10:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@11:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@12:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@13:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@14:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@15:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@16:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
	JR R5
	
	ENDP

	ENDI

	IF DEFINED intybasic_ecs
	ORG $4800	; Available up to $4FFF

        ; Disable ECS ROMs so that they don't conflict with us
        MVII    #$2A5F, R0
        MVO     R0,     $2FFF
        MVII    #$7A5F, R0
        MVO     R0,     $7FFF
        MVII    #$EA5F, R0
        MVO     R0,     $EFFF

        B       $1041       ; resume boot

	ENDI

        ORG $200,$200,"-RWB"

Q2:	; Reserved label for #BACKTAB

	ORG $319,$319,"-RWB"
        ;
        ; 16-bits variables
	; Note IntyBASIC variables grow up starting in $308.
        ;
        IF DEFINED intybasic_voice
IV.Q:      RMB 8    ; IV_xxx        16-bit          Voice queue  (8 words)
IV.FPTR:   RMB 1    ; IV_xxx        16-bit          Current FIFO ptr.
IV.PPTR:   RMB 1    ; IV_xxx        16-bit          Current Phrase ptr.
        ENDI

        ORG $323,$323,"-RWB"

_scroll_buffer: RMB 20  ; Sometimes this is unused
_music_table:	RMB 1	; Note table
_music_start:	RMB 1	; Start of music
_music_p:	RMB 1	; Pointer to music
_frame:         RMB 1   ; Current frame
_read:          RMB 1   ; Pointer to DATA
_gram_bitmap:   RMB 1   ; Bitmap for definition
_gram2_bitmap:  RMB 1   ; Secondary bitmap for definition
_screen:    RMB 1       ; Pointer to current screen position
_color:     RMB 1       ; Current color

Q1:			; Reserved label for #MOBSHADOW
_mobs:      RMB 3*8     ; MOB buffer

_col0:      RMB 1       ; Collision status for MOB0
_col1:      RMB 1       ; Collision status for MOB1
_col2:      RMB 1       ; Collision status for MOB2
_col3:      RMB 1       ; Collision status for MOB3
_col4:      RMB 1       ; Collision status for MOB4
_col5:      RMB 1       ; Collision status for MOB5
_col6:      RMB 1       ; Collision status for MOB6
_col7:      RMB 1       ; Collision status for MOB7

SCRATCH:    ORG $100,$100,"-RWBN"
        ;
        ; 8-bits variables
        ;
ISRVEC:     RMB 2       ; Pointer to ISR vector (required by Intellivision ROM)
_int:       RMB 1       ; Signals interrupt received
_ntsc:      RMB 1       ; Signals NTSC Intellivision
_rand:      RMB 1       ; Pseudo-random value
_gram_target:   RMB 1   ; Contains GRAM card number
_gram_total:    RMB 1   ; Contains total GRAM cards for definition
_gram2_target:  RMB 1   ; Contains GRAM card number
_gram2_total:   RMB 1   ; Contains total GRAM cards for definition
_mode_select:   RMB 1   ; Graphics mode selection
_border_color:  RMB 1   ; Border color
_border_mask:   RMB 1   ; Border mask
    IF DEFINED intybasic_keypad
_cnt1_p0:   RMB 1       ; Debouncing 1
_cnt1_p1:   RMB 1       ; Debouncing 2
_cnt1_key:  RMB 1       ; Currently pressed key
_cnt2_p0:   RMB 1       ; Debouncing 1
_cnt2_p1:   RMB 1       ; Debouncing 2
_cnt2_key:  RMB 1       ; Currently pressed key
    ENDI
    IF DEFINED intybasic_scroll
_scroll_x:  RMB 1       ; Scroll X offset
_scroll_y:  RMB 1       ; Scroll Y offset
_scroll_d:  RMB 1       ; Scroll direction
    ENDI
    IF DEFINED intybasic_music
_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
_music_tc:  RMB 1       ; Time counter
_music_t:   RMB 1       ; Time base
_music_i1:  RMB 1       ; Instrument 1 
_music_s1:  RMB 1       ; Sample pointer 1
_music_n1:  RMB 1       ; Note 1
_music_i2:  RMB 1       ; Instrument 2
_music_s2:  RMB 1       ; Sample pointer 2
_music_n2:  RMB 1       ; Note 2
_music_i3:  RMB 1       ; Instrument 3
_music_s3:  RMB 1       ; Sample pointer 3
_music_n3:  RMB 1       ; Note 3
_music_s4:  RMB 1       ; Sample pointer 4
_music_n4:  RMB 1       ; Note 4 (really it's drum)

_music_freq10:	RMB 1   ; Low byte frequency A
_music_freq20:	RMB 1   ; Low byte frequency B
_music_freq30:	RMB 1   ; Low byte frequency C
_music_freq11:	RMB 1   ; High byte frequency A
_music_freq21:	RMB 1   ; High byte frequency B
_music_freq31:	RMB 1   ; High byte frequency C
_music_mix:	RMB 1   ; Mixer
_music_noise:	RMB 1   ; Noise
_music_vol1:	RMB 1   ; Volume A
_music_vol2:	RMB 1   ; Volume B
_music_vol3:	RMB 1   ; Volume C
    ENDI
    IF DEFINED intybasic_music_volume
_music_vol:	RMB 1	; Global music volume
    ENDI
    IF DEFINED intybasic_voice
IV.QH:     RMB 1    ; IV_xxx        8-bit           Voice queue head
IV.QT:     RMB 1    ; IV_xxx        8-bit           Voice queue tail
IV.FLEN:   RMB 1    ; IV_xxx        8-bit           Length of FIFO data
    ENDI


V9:	RMB 1	; IMUSICINST
V2:	RMB 1	; IMUSICSCROLL
V7:	RMB 1	; IMUSICVOLCHECK
V8:	RMB 1	; IMUSICVOLLAST
V5:	RMB 1	; IMUSICX
V6:	RMB 1	; INTYNOTE
V4:	RMB 1	; KEYCLEAR
V3:	RMB 1	; TOGGLE
Q14:	RMB 3	; IMUSICDRAWNOTE
Q3:	RMB 3	; IMUSICNOTECOLOR
Q12:	RMB 3	; IMUSICNOTELAST
Q13:	RMB 3	; IMUSICVOLUMELAST
_SCRATCH:	EQU $

SYSTEM:	ORG $2F0, $2F0, "-RWBN"
STACK:	RMB 24
V1:	RMB 1	; #INTYMUSICBLINK
V10:	RMB 1	; #X
Q10:	RMB 3	; #IMUSICINST
Q8:	RMB 3	; #IMUSICNOTE
Q4:	RMB 3	; #IMUSICPIANOCOLORA
Q5:	RMB 3	; #IMUSICPIANOCOLORB
Q11:	RMB 2	; #IMUSICTIME
Q9:	RMB 3	; #IMUSICVOL
_SYSTEM:	EQU $
F20:	EQU IMUSICGETINFO
F19:	EQU IMUSICKILL
F25:	EQU MUSICSCROLL
