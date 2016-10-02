'IntyMusic by Marco A. Marrero.  Started at 7/30/2016, v8/10/2016, big revision: v10/1/2016

'----Required----
ON FRAME GOSUB DoStuffAfterWait
INCLUDE "constants.bas"
PLAY FULL
DIM iMusicNoteColor(3)		'Note color 
DIM #iMusicPianoColorA(3)
DIM #iMusicPianoColorB(3)

'========================== Options #1 - customization ========================================
INTYMUSIC_PLAY_VOLUME = 15		'--- PLAY VOLUME. 0=silence, 15=maximum. Also used by Volume meter

INTYMUSIC_NEW_AUTO_SCROLL = 5	'--- 0=scroll only when any note changes, 1=scroll every frame (fast!), 2=skip one frame, 3=skip 2, etc.
							'---- Large numbers will not freeze player, it always scrolls when any note plays and resets count to 0
							'---- In previous versions, it was 1 or 0. Use 4 or 5 on this version instead

INTYMUSIC_FANFOLD = 1			'--- 1 for alternating colors, like classic dot-matrix paper

INTYMUSIC_STAFF_COLOR	= FG_BLACK	'-- staff color. Colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
INTYMUSIC_TITLE_COLOR = FG_BLUE	'---Song title Color
INTYMUSIC_SONG_TITLE = 1			'--- 0 to disable vertical song title

'--- volume bar on each sound channel---
INTYMUSIC_VOLUMECARD = 43		'--- GRAM card,back of volume bar. 40 to 43. 40 is static/solid, 41 is checkerboard, 42=recommended, 43=bandaid.

'--- Music note color, by voice channel (drawn on top, scrolls down)----
iMusicNoteColor(0)=FG_DARKGREEN
iMusicNoteColor(1)=FG_RED
iMusicNoteColor(2)=FG_BLUE

'--- Piano key and Volume colors, by voice channel -- 2nd set flash effect. Use same colors on 2nd to disable hilite/blink
' SPR_BLACK,SPR_BLUE,SPR_RED,SPR_TAN,SPR_DARKGREEN,SPR_GREEN,SPR_YELLOW,SPR_WHITE,SPR_GREY,SPR_CYAN,SPR_ORANGE,SPR_BROWN,SPR_PINK,SPR_LIGHTBLUE,SPR_YELLOWGREEN,SPR_PURPLE			7
'--1st set---
#iMusicPianoColorA(0)=SPR_DARKGREEN
#iMusicPianoColorA(1)=SPR_RED
#iMusicPianoColorA(2)=SPR_BLUE
'--2nd set, flash---
#iMusicPianoColorB(0)=SPR_GREEN
#iMusicPianoColorB(1)=SPR_ORANGE
#iMusicPianoColorB(2)=SPR_LIGHTBLUE

'----Color stack----alternating background colors. STACK_BLACK,STACK_BLUE,STACK_RED,STACK_TAN,STACK_DARKGREEN,STACK_GREEN,STACK_YELLOW,STACK_WHITE
'STACK_GREY,STACK_CYAN,STACK_ORANGE,STACK_BROWN,STACK_PINK,STACK_LIGHTBLUE,STACK_YELLOWGREEN,STACK_PURPLE

BORDER BORDER_WHITE,0
MODE 0,STACK_WHITE,STACK_TAN,STACK_WHITE,STACK_TAN
'MODE 0,STACK_GREY,STACK_LIGHTBLUE,STACK_WHITE,STACK_GREEN
'MODE 0,STACK_YELLOWGREEN,STACK_DARKGREEN,STACK_WHITE,STACK_GREEN
 
'========================== Options #1 End ===========================================================

'-----Required------ 
INCLUDE "IntyMusicPlayer.bas"		'Main music player
INCLUDE "IntyMusicCredits.bas"		'Title screen
INCLUDE "IntyMusic_Playlist.bas"	'Menu
INCLUDE "IntyMusicData.bas"		'Look up tables

INCLUDE "IntyMusicGraphics.bas"	'GRAM cards
INCLUDE "IntyMusicASM.bas"			'ASM PROC, mainly to read vars from IntyBasic_epilogue and custom scroll 

'========================== Options #2 - More customization ==============================================

'---------------- Song name, called from the title screen -------------------
IntyMusicInit_Credits: PROCEDURE
	'--colors:FG_BLACK,FG_BLUE,FG_RED,FG_TAN,FG_DARKGREEN,FG_GREEN,FG_YELLOW,FG_WHITE
	PRINT COLOR FG_DARKGREEN	
	PRINT AT 060," "	
	'20 char max 1234567890123456789
	PRINT COLOR FG_BLACK
	PRINT AT 080,"Song title goes here"
	PRINT COLOR FG_DARKGREEN
	PRINT AT 100,"Additional text here"
	PRINT COLOR FG_GREEN
	PRINT AT 120,"Extra text goes here"
END	

'========= Playlist =====================================================================================
'1. Remove PLAY/MUSIC label, or, leave and comment the ones defined here.
'2. Modify the menu to PRINT items
'

IntyMusic_Playlist_Play: PROCEDURE	
	iMusicSelection=1
	'GOSUB IntyMusic_PlayList_Menu		'<---- Comment line to skip the menu, play 1st song
	
	'--Selection done. Play song-----
	iMusicSelection=iMusicSelection-1	'--Selection must start at 0..
	PLAY VOLUME INTYMUSIC_PLAY_VOLUME	'--Ready to play
	WAIT

	ON iMusicSelection GOTO Song1,Song2,Song3,Song4,Song5,Song6,Song7,Song8,Song9,Song10,Song11,Song12,Song13,Song14,Song15,Song16,Song17,Song18,Song19,Song20,Song21,Song22,Song23,Song24,Song25

	Song1: #x=VARPTR MyMusicTitle(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic:GOTO Exit_IntyMusic_Play_Song
	Song2: #x=VARPTR MyMusicTitle2(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic2:GOTO Exit_IntyMusic_Play_Song
	Song3: #x=VARPTR MyMusicTitle3(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic3:GOTO Exit_IntyMusic_Play_Song
	Song4: #x=VARPTR MyMusicTitle4(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic4:GOTO Exit_IntyMusic_Play_Song
	Song5: #x=VARPTR MyMusicTitle5(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic5:GOTO Exit_IntyMusic_Play_Song
	Song6: #x=VARPTR MyMusicTitle6(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic6:GOTO Exit_IntyMusic_Play_Song
	Song7: #x=VARPTR MyMusicTitle7(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic7:GOTO Exit_IntyMusic_Play_Song
	Song8: #x=VARPTR MyMusicTitle8(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic8:GOTO Exit_IntyMusic_Play_Song
	Song9: #x=VARPTR MyMusicTitle9(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic9:GOTO Exit_IntyMusic_Play_Song
	Song10: #x=VARPTR MyMusicTitle10(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic10:GOTO Exit_IntyMusic_Play_Song
	Song11: #x=VARPTR MyMusicTitle11(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic11:GOTO Exit_IntyMusic_Play_Song
	Song12: #x=VARPTR MyMusicTitle12(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic12:GOTO Exit_IntyMusic_Play_Song
	Song13: #x=VARPTR MyMusicTitle13(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic13:GOTO Exit_IntyMusic_Play_Song
	Song14: #x=VARPTR MyMusicTitle14(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic14:GOTO Exit_IntyMusic_Play_Song
	Song15: #x=VARPTR MyMusicTitle15(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic15:GOTO Exit_IntyMusic_Play_Song
	Song16: #x=VARPTR MyMusicTitle16(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic16:GOTO Exit_IntyMusic_Play_Song
	Song17: #x=VARPTR MyMusicTitle17(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic17:GOTO Exit_IntyMusic_Play_Song
	Song18: #x=VARPTR MyMusicTitle18(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic18:GOTO Exit_IntyMusic_Play_Song
	Song19: #x=VARPTR MyMusicTitle19(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic19:GOTO Exit_IntyMusic_Play_Song
	Song20: #x=VARPTR MyMusicTitle20(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic20:GOTO Exit_IntyMusic_Play_Song
	Song21: #x=VARPTR MyMusicTitle21(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic21:GOTO Exit_IntyMusic_Play_Song
	Song22: #x=VARPTR MyMusicTitle22(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic22:GOTO Exit_IntyMusic_Play_Song
	Song23: #x=VARPTR MyMusicTitle23(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic23:GOTO Exit_IntyMusic_Play_Song
	Song24: #x=VARPTR MyMusicTitle24(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic24:GOTO Exit_IntyMusic_Play_Song
	Song25: #x=VARPTR MyMusicTitle25(0):GOSUB IntyMusic_CopySongTitle:PLAY MyMusic25:GOTO Exit_IntyMusic_Play_Song
	GOSUB IntyMusic_PlayList_Menu	'to avoid compiler warning if it is uncommented
Exit_IntyMusic_Play_Song:	
END

IntyMusic_CopySongTitle: PROCEDURE	
	IF PEEK(#x)="*" THEN #x=VARPTR MyDefaultName(0)	'-if it is *, pick default name
	
	FOR iMusicX=0 TO 11	'Read, if $FF, pad rest with spaces
		iMusicY=PEEK(#x):IF iMusicY=$FF THEN iMusicY=" " ELSE #x=#x+1
		MyMusicName(iMusicX)=iMusicY
	NEXT iMusicX	
	ScrollDelay=6:GOSUB ScrollStaffToStartPlay
END

MyDefaultName:
DATA " IntyMusic",$FF	'--Default name. 12 characters MAX. Use $FF to terminate (space IS zero!!)

'=======================================Songs to use======================================================
asm ORG $C040		;---big segment for music

'Please remove the "MyMusic" label from the INCLUDEd file. If you prefer to leave the label, uncomment the label below.

MyMusic:
INCLUDE "songs\SHarrierC64.bas"
DATA 8:MUSIC STOP			'To avoid playing random data if there is no song
MyMusicTitle:
DATA "SpaceHarrier",$FF	'12 characters max, $FF to terminate

'=================================================================================
MyMusic2:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP	'To avoid playing random data if there is no song
MyMusicTitle2:
DATA "*",$FF		'12 characters max, $FF to terminate (I cannot use null, it is " ")

'=================================================================================
MyMusic3:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle3:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic4:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle4:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic5:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle5:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic6:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle6:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic7:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle7:
DATA "*",$FF		'12 characters max, $FF to terminated.

'=================================================================================
MyMusic8:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle8:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic9:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle9:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic10:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle10:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic11:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle11:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic12:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle12:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic13:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle13:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic14:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle14:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic15:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle15:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic16:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle16:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic17:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle17:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic18:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle18:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic19:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle19:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic20:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle20:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic21:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle21:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic22:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle22:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic23:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle23:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic24:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle24:
DATA "*",$FF		'12 characters max, $FF to terminate

'=================================================================================
MyMusic25:
'INCLUDE "songs\songname.bas"
DATA 8:MUSIC STOP
MyMusicTitle25:
DATA "*",$FF		'12 characters max, $FF to terminate

'---IntyBasic epilogue------
asm ORG $A000