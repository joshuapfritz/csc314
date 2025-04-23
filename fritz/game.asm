%include "/usr/local/share/csc314/asm_io.inc"

; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define WALL_CHAR '#'
%define PLAYER_CHAR 'O'
%define MYSTERY_CHAR '?'
%define EMPTY_CHAR ' '
	; #### added MYSTERY_CHAR and EMPTY_CHAR for teleport/bomb

; the size of the game screen in characters
%define HEIGHT 20
%define WIDTH 40

; the player starting position.
; top left is considered (0,0)
%define STARTX 1
%define STARTY 1

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'w'
%define LEFTCHAR 'a'
%define DOWNCHAR 's'
%define RIGHTCHAR 'd'


segment .data

	; used to fopen() the board file defined above
	board_file			db BOARD_FILE,0

	; used to change the terminal mode
	mode_r				db "r",0
	raw_mode_on_cmd		db "stty raw -echo",0
	raw_mode_off_cmd	db "stty -raw echo",0

	; ANSI escape sequence to clear/refresh the screen
	clear_screen_code	db	27,"[2J",27,"[H",0

	; things the program will print
	help_str			db 13,10,"Controls: ", \
							UPCHAR,"=UP / ", \
							LEFTCHAR,"=LEFT / ", \
							DOWNCHAR,"=DOWN / ", \
							RIGHTCHAR,"=RIGHT / ", \
							EXITCHAR,"=EXIT", \
							13,10,10,0

	board_end dd 0                  ; Placeholder for board_end address needed for checks in bomb

segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resd	1
	ypos	resd	1

segment .text

	global	asm_main
	global  raw_mode_on
	global  raw_mode_off
	global  init_board
	global  render
	; Add new subroutines for mystery squares and their functions.
	global	is_mystery_square
    global	teleport
    global	bomb
    global	clear_tile_if_in_bounds

	extern	system
	extern	putchar
	extern	getchar
	extern	printf
	extern	fopen
	extern	fread
	extern	fgetc
	extern	fclose

asm_main:
	push	ebp
	mov		ebp, esp

	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable
	call	init_board

	; set the player at the proper start position
	mov		DWORD [xpos], STARTX
	mov		DWORD [ypos], STARTY

	; the game happens in this loop
	; the steps are...
	;   1. render (draw) the current board
	;   2. get a character from the user
	;	3. store current xpos,ypos in esi,edi
	;	4. update xpos,ypos based on character from user
	;	5. check what's in the buffer (board) at new xpos,ypos
	;	6. if it's a wall, reset xpos,ypos to saved esi,edi
	;	7. otherwise, just continue! (xpos,ypos are ok)
	game_loop:

		; draw the game board
		call	render

		; get an action from the user
		call	getchar

		; store the current position
		; we will test if the new position is legal
		; if not, we will restore these
		mov		esi, DWORD [xpos]
		mov		edi, DWORD [ypos]

		; choose what to do
		cmp		eax, EXITCHAR
		je		game_loop_end
		cmp		eax, UPCHAR
		je 		move_up
		cmp		eax, LEFTCHAR
		je		move_left
		cmp		eax, DOWNCHAR
		je		move_down
		cmp		eax, RIGHTCHAR
		je		move_right
		jmp		input_end			; or just do nothing

		; move the player according to the input character
		move_up:
			dec		DWORD [ypos]
			jmp		input_end
		move_left:
			dec		DWORD [xpos]
			jmp		input_end
		move_down:
			inc		DWORD [ypos]
			jmp		input_end
		move_right:
			inc		DWORD [xpos]
		input_end:

		; (W * y) + x = pos

		; compare the current position to the wall character
		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, DWORD [xpos]
		lea		eax, [board + eax]
		cmp		BYTE [eax], WALL_CHAR
		jne		valid_move
; ##### compare to MYSTERY_CHAR #####
		cmp		BYTE [eax], MYSTERY_CHAR
		je		is_mystery_square

			; opps, that was an invalid move, reset
			mov		DWORD [xpos], esi
			mov		DWORD [ypos], edi
		valid_move:
			jmp		game_loop

	game_loop_end:

	; restore old terminal functionality
	call raw_mode_off

	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

raw_mode_on:

	push	ebp
	mov		ebp, esp

	push	raw_mode_on_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

raw_mode_off:

	push	ebp
	mov		ebp, esp

	push	raw_mode_off_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

init_board:

	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	board_file
	call	fopen
	add		esp, 8
	mov		DWORD [ebp - 4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp - 8], 0
	read_loop:
	cmp		DWORD [ebp - 8], HEIGHT
	je		read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp - 8]
		lea		ebx, [board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp - 4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp - 4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp - 8]
	jmp		read_loop
	read_loop_end:

	jmp		add_random_blocks

	; close the open file handle
	push	DWORD [ebp - 4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

render:

	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	sub		esp, 8

	; clear the screen
	push	clear_screen_code
	call	printf
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp - 4], 0
	y_loop_start:
	cmp		DWORD [ebp - 4], HEIGHT
	je		y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp - 8], 0
		x_loop_start:
		cmp		DWORD [ebp - 8], WIDTH
		je 		x_loop_end

			; check if (xpos,ypos)=(x,y)
			mov		eax, DWORD [xpos]
			cmp		eax, DWORD [ebp - 8]
			jne		print_board
			mov		eax, DWORD [ypos]
			cmp		eax, DWORD [ebp - 4]
			jne		print_board
				; if both were equal, print the player
				push	PLAYER_CHAR
				call	putchar
				add		esp, 4
				jmp		print_end
			print_board:
				; otherwise print whatever's in the buffer
				mov		eax, DWORD [ebp - 4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, DWORD [ebp - 8]
				mov		ebx, 0
				mov		bl, BYTE [board + eax]
				push	ebx
				call	putchar
				add		esp, 4
			print_end:

		inc		DWORD [ebp - 8]
		jmp		x_loop_start
		x_loop_end:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp - 4]
	jmp		y_loop_start
	y_loop_end:

	mov		esp, ebp
	pop		ebp
	ret
; ###################################################################
; Add random MYSTERY_CHAR blocks based on 1% of the gameboard area
add_random_blocks:
	; Calculate NUM_MYSTERY_BLOCKS = (WIDTH * HEIGHT) / 100
	mov		eax, WIDTH
	mov		ecx, HEIGHT
	mul		ecx                  ; eax = WIDTH * HEIGHT
	xor		edx, edx
	mov		ecx, 100
	div		ecx                     ; eax = (WIDTH * HEIGHT) / 100
	mov		ebx, eax                ; ebx = NUM_MYSTERY_BLOCKS

	random_block_loop:
		cmp		ebx, 0
		je		random_blocks_done      ; Exit if all blocks are added

		; Generate deterministic positions
		; Use (block index * prime) % area for pseudo-random distribution
		mov		eax, ebx                ; eax = block index
		mov		ecx, 31				    ; must be a prime number for proper calculation
		mul		ecx                     ; eax = block index * PRIME_NUMBER
		xor		edx, edx
		mov		ecx, WIDTH
		mov		esi, HEIGHT
		mul		esi                  ; ecx = WIDTH * HEIGHT
		div		ecx                     ; edx = (block index * PRIME_NUMBER) % area

		; Calculate row and column from edx
		mov		eax, edx                ; eax = offset in 1D array
		xor		edx, edx
		mov		ecx, WIDTH
		div		ecx                     ; edx = row, eax = column
		mov		edi, edx                ; Save row in edi
		mov		esi, eax                ; Save column in esi

		; Calculate offset in the board array
		mov		eax, WIDTH
		mul		edi                     ; eax = row * WIDTH
		add		eax, esi                ; eax = row * WIDTH + column
		mov		ebx, eax   

		; Check if the cell is empty
		mov     al, BYTE [board + ebx]  ; Load current board cell
		cmp     al, ' '                 ; Check if the cell is empty
		jne     skip_placement          ; Skip if it's not empty

		; Place MYSTERY_CHAR
		mov     BYTE [board + ebx], MYSTERY_CHAR

	skip_placement:
		; Decrement block counter
		dec		ebx
		jmp		random_block_loop

random_blocks_done:
; End MYSTERY BLOCK Generation
; calculate board_end for bombs.
    lea     eax, [board + (HEIGHT * WIDTH)] ; Calculate board_end
    mov     DWORD [board_end], eax          ; Store board_end address
	ret			; Go back to init_board to close out file and return to the game.

;##########################################################################

; ##### Handle Mystery square #####
is_mystery_square:
	; Generate a pseudo-random number based on xpos and ypos like in the board_init to place random.
	mov     eax, DWORD [xpos]        ; Load xpos
	mov     ebx, DWORD [ypos]        ; Load ypos
	add     eax, ebx                 ; Combine positions to create a unique block index
	mov     ecx, 31                  ; Use a prime number as a multiplier
	mul     ecx                      ; eax = (xpos + ypos) * PRIME_NUMBER
	xor     edx, edx
	mov     ecx, WIDTH
	mov		esi, HEIGHT
	mul     esi                   ; ecx = WIDTH * HEIGHT
	div     ecx                      ; edx = (block index * PRIME_NUMBER) % area
	mov     eax, edx                 ; eax = random value in range 0–(WIDTH * HEIGHT - 1)

	; Scale to desired range (0–99)
	xor     edx, edx
	mov     ecx, 100                 ; Target range is 0–99
	div     ecx                      ; edx = eax % 100

	; Check the result range
	cmp     eax, 50
	jl      teleport                 ; 0–49: Teleport
	cmp     eax, 100
	jl      bomb                     ; 50–74: Bomb
	ret
; ####### END: Mystery square ########
; ## Adjust the values and add jumps 
; ## to add a bag of coins or add
; ## big point squares, etc.
; ####################################
; ##### MYSTERY BLOCK ACTIONS ########
; ####################################
teleport:
    ; Generate a pseudo-random number based on xpos and ypos like in the board_init to place random.
    mov     eax, DWORD [xpos]        ; Load xpos
    mov     ebx, DWORD [ypos]        ; Load ypos
    add     eax, ebx                 ; Combine positions to create a unique block index
    mov     ecx, 31                  ; Use a prime number as a multiplier
    mul     ecx                      ; eax = (xpos + ypos) * PRIME_NUMBER
    xor     edx, edx
    mov     ecx, WIDTH
    mov		esi, HEIGHT
    mul     esi                      ; ecx = WIDTH * HEIGHT
    div     ecx                      ; edx = (block index * PRIME_NUMBER) % area
    mov     eax, edx                 ; eax = random value in range 0–(WIDTH * HEIGHT - 1)

    ; Scale to desired range (0–WIDTH * HEIGHT - 1)
    xor     edx, edx
    mov     ecx, WIDTH
    div     ecx                      ; edx = eax % WIDTH
    mov     esi, edx                 ; esi = random column

    ; Calculate the row
    mov     eax, edx
    div     esi
    mov     edi, edx                 ; edi = random row

    ; Check if the new position is valid (not a wall or mystery square)
    ; Calculate offset in the board array
    mov     eax, edi                 ; eax = row
    mov     ebx, WIDTH
    mul     ebx                      ; eax = row * WIDTH
    add     eax, esi                 ; eax = row * WIDTH + column
    mov     ebx, eax

    ; Check if the new position is a wall or a mystery square
    mov     al, BYTE [board + ebx]   ; Load current board cell
    cmp     al, WALL_CHAR            ; If it's a wall
    je      teleport                 ; If it's a wall, try again
    cmp     al, MYSTERY_CHAR         ; If it's a mystery square
    je      teleport                 ; If it's a mystery square, try again

    ; If the new position is valid, update xpos and ypos
    mov     DWORD [xpos], esi        ; Update xpos (column)
    mov     DWORD [ypos], edi        ; Update ypos (row)
    ret

bomb:
    ; Bomb explodes in a + (2 up/down, 4 left/right) and clears the spaces,
	; Player moves to bomb's position.
    ; Start from the current position (xpos, ypos)
	;bomb_logic --- pseudocode:
    ; Clear vertical area (2 up, 2 down)
    ;for i = ypos - 2 to ypos + 2:
    ;    if i within bounds:
    ;        clear_tile(xpos, i)
    ; Clear horizontal area (4 left, 4 right)
    ;for j = xpos - 4 to xpos + 4:
    ;    if j within bounds:
    ;        clear_tile(j, ypos)
    ; Continue game

    mov     esi, DWORD [xpos]         ; Store xpos in esi
    mov     edi, DWORD [ypos]         ; Store ypos in edi

    ; Clear vertically (2 blocks up and down)
    mov     ecx, 2   	              ; up/down counter
clear_vertical:
    ; Clear tile at (xpos, ypos - ecx)
    mov eax, edi            ; eax = ypos
    sub eax, ecx            ; eax = ypos - ecx
    call clear_tile_if_in_bounds  ; Check and clear if within bounds

    ; Clear tile at (xpos, ypos + ecx)
    mov eax, edi            ; eax = ypos
    add eax, ecx            ; eax = ypos + ecx
    call clear_tile_if_in_bounds  ; Check and clear if within bounds

    loop clear_vertical      ; Repeat for range

    ; Clear horizontal area (4 squares left and right)
    mov ecx, 4              ; Counter for left/right range
clear_horizontal:
    ; Clear tile at (xpos - ecx, ypos)
    mov eax, esi            ; eax = xpos
    sub eax, ecx            ; eax = xpos - ecx
    call clear_tile_if_in_bounds  ; Check and clear if within bounds

    ; Clear tile at (xpos + ecx, ypos)
    mov eax, esi            ; eax = xpos
    add eax, ecx            ; eax = xpos + ecx
    call clear_tile_if_in_bounds  ; Check and clear if within bounds

    loop clear_horizontal   ; Repeat for range

    ; Return to game loop
    jmp game_loop

    ; Check if position (eax, edi) is within board bounds
    ; (eax = xpos or ypos, edi = ypos or xpos)
    ; Replace with your board boundary checking logic
    ; If valid:
clear_tile_if_in_bounds:
    ; Check if index is within bounds
    cmp eax, 0                  ; Index must be >= 0
    jl out_of_bounds             ; If less, exit
    cmp eax, [board_end]        ; Compare index with board size
    jge out_of_bounds            ; If >= board size, exit

    ; Clear tile at index by setting it to EMPTY_CHAR
    mov al, [EMPTY_CHAR]         ; Load EMPTY_CHAR value
    mov [board + eax], al        ; Overwrite board tile with EMPTY_CHAR

out_of_bounds:
    ret
