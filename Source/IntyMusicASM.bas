'    _______________
'___/ IMUSICGETINFO2 \________________________________________________________________
'Get IntyBasic_epilogue data onto IntyBasic. Ill copy note and volume.
'Call IMUSICGETINFO(VARPTR iMusicVol(0-2), VARPTR iMusicNote(0-2), VARPTR iMusicWaveform(0-2),VARPTR iMusicTime(0-3))	
ASM IMUSICGETINFOV2: PROC	
'r0 = 1st parameter, VARPTR iMusicVol(0)
'r1 = 2nd parameter, VARPTR iMusicNote(0)
'r2 = 3rd parameter, VARPTR iMusicWaveform(0)
'r3 = 4rd parameter, VARPTR iMusicTime(0)
'asm pshr r5				;push return
		
'--- iMusicTime(0)=_music_t (Time Base),iMusicTime(1)=_music_tc (note time), iMusicTime(2)=_music_frame (0 to 5) 0=skipped frame!
	asm movr	r3,r4				; r3 --> r4 		r4=&iMusicTime(0)
	asm mvi _music_t,r3			; _music_t --> r3 (time base)
	asm decr r3 					; r3-- (time base=time base - 1)
	asm mvo@ r3,r4				; r3 --> [r4++]	
	
	asm mvi	_music_tc,r3			; _music_tc --> r3 (time)	
	asm mvo@ r3,r4				; r3 --> [r4++]

	asm mvi	_music_frame,r3		; _music_frame --> r3 (time, 0 to 5). In pal, it should be always zero...
	asm add	_ntsc,r3				; if NTSC then r3++ (time is now 1 to 6, now I can test if it is 1 when skipped)
	asm mvo@ r3,r4				; r3 --> [r4++]
	
	asm cmpi #1,r3				; if (r3==1) then music skipped! We already have all the values, no need to re-read
	asm beq @@GoodBye		

'---- get volume, to know when same note played again ---
	asm movr	r0,r4			;r0 --> r4 (r4=r0=&iMusicVol(0))
	
	asm mvi	_music_vol1,r3	;  --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_vol2,r3	; --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_vol3,r3	; --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	
'--- get notes ---
	asm movr	r1,r4			;r1 --> r4. (r4=&iMusicNote(0))
	asm mvi	_music_n1,r3		;_music_n1 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_n2,r3 	;_music_n2 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]
	asm mvi	_music_n3,r3		;_music_n3 --> r3
	asm mvo@ r3,r4			;r3 --> [r4++]

'--- Get WaveForm (to detect if same note went again) ----iMusicWaveform(x) ----
	asm movr r2,r4				;r2 --> r4  (r4= &iMusicWaveform(0))
	asm mvi _music_s1,r3
	asm mvo@ r3,r4				; r3 --> [r4++]
	asm mvi _music_s2,r3
	asm mvo@ r3,r4				; r3 --> [r4++]
	asm mvi _music_s3,r3
	asm mvo@ r3,r4				; r3 --> [r4++]

'-------------------------------------------------------------	
asm @@GoodBye:
	asm jr	r5				;return 
	
	'asm	pulr pc				;return 
	'asm mvi@ r3,r3				; Get pointer, r3=[r3] 
	'asm xorr	r3,r3 			; r3=0
asm ENDP


'    ____________
'___/ MUSICSCROLL \____________________ 
'Only Scroll 10 rows, and only columns 2 to 18 (17 lines)
ASM MUSICSCROLL: PROC	
		
	asm mvii #$0200 + 198,r2		;#BackTAB + 198--> R2
	asm mvii	#$0200 + 178,r3		;Line above --> r3 
	asm mvii #9,r1				;Loop 9 lines
	asm mvii #2,r4				;Skip 2 chars
	
asm @@CopyLoop:
	asm REPEAT 18
		asm mvi@ r3,r0		;[r3] --> R0
		asm decr r3
		asm mvo@ r0,r2		;r0 --> [R2]		
		asm decr r2 
	asm ENDR
	
	asm subr r4,r2		;skip 3 chars 
	asm subr r4,r3 
	
	asm decr r1			;done row..
	asm bne @@CopyLoop
	
	asm jr	r5				;return
	'asm	pulr pc				;return 
asm ENDP		

'    ____________
'___/ IMUSICKILL \___________________________
'PLAY NONE seems not to work.... 
ASM IMUSICKILL: PROC	
		
'--- kill notes ---
	asm xorr r0,r0			;clear r0
	asm mvo	r0,_music_n1
	asm mvo	r0,_music_n2
	asm mvo 	r0,_music_n3
	asm jr	r5				;return 
asm ENDP

'==============================================================================
'From IntyBasic_epilogue.asm

'_music_table:	RMB 1	; Note table
'_music_start:	RMB 1	; Start of music
'_music_p:	RMB 1	; Pointer to music
'- - - - - - -
'_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
'_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
'_music_tc:  RMB 1       ; Time counter
'_music_t:   RMB 1       ; Time base
'_music_i1:  RMB 1       ; Instrument 1 
'_music_s1:  RMB 1       ; Sample pointer 1
'_music_n1:  RMB 1       ; Note 1
'_music_i2:  RMB 1       ; Instrument 2
'_music_s2:  RMB 1       ; Sample pointer 2
'_music_n2:  RMB 1       ; Note 2
'_music_i3:  RMB 1       ; Instrument 3
'_music_s3:  RMB 1       ; Sample pointer 3
'_music_n3:  RMB 1       ; Note 3
'_music_s4:  RMB 1       ; Sample pointer 4
'_music_n4:  RMB 1       ; Note 4 (really it's drum)
'-----
'_music_freq10:	RMB 1   ; Low byte frequency A
'_music_freq20:	RMB 1   ; Low byte frequency B
'_music_freq30:	RMB 1   ; Low byte frequency C
'_music_freq11:	RMB 1   ; High byte frequency A
'_music_freq21:	RMB 1   ; High byte frequency B
'_music_freq31:	RMB 1   ; High byte frequency C
'_music_mix:	RMB 1   ; Mixer
'_music_noise:	RMB 1   ; Noise
'_music_vol1:	RMB 1   ; Volume A
'_music_vol2:	RMB 1   ; Volume B
'_music_vol3:	RMB 1   ; Volume C
'_music_vol:	RMB 1	; Global music volume

