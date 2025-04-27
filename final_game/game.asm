%include "/usr/local/share/csc314/asm_io.inc"

; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define WALL_CHAR '#'
%define PLAYER_ONE 'O' ; Variable for player one
%define PLAYER_TWO 'X' ; Variable for player two
%define MYSTERY_CHAR '?' ; Mystery block
%define BLANK_CHAR ' '	; Blank space

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
	
	number db " 1    2 ", 0 ; Text for showing which numbers to write
	options db " O or X ", 0 ; Shows what the options are
	choice db "Enter which character you want to play: ", 0 ; Tells the player to choose which character they want to play
	gold_coins db "You collected a gold coin!", 0  ; Tells the player when they have collected a gold coin
	current_score db "Score: ", 0  ; Displays current score
	current_coins db "Coins: ", 0 ; Displays current number of coins
	game_over  db "GAME OVER", 0 ; game over message

	X dd 0 ; This is part of the wall subprogram for deciding the X portion of the wall
	Y dd 0 ; This is part of the wall subprogram for deciding the Y portion of the wall
	P dd 2 ; This value decides which character is shown when playing

	po dd 1 ; Used to check if the character want to play as O
	px dd 2 ; Used to check if the character want to play as X

	R dd 0 ; Random number storage
	BAREA dd 0	; Board Area
	SEED dd 0	; P-RNG seed value.

segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	NUM_MYSTERY_BLOCKS resd 1

	; these variables store the current player position
	xpos	resd	1
	ypos	resd	1
	coin_xpos  resd 1 ; track the coins current x position
	coin_ypos  resd 1 ; track the coins current y position

	num_coins  resd 1  ; stores the number of coins the player has
	score  resd 1  ; stores the player's current score

segment .text

	global	asm_main
	global  raw_mode_on
	global  raw_mode_off
	global  init_board
	global  render

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

	player_choice: ; Checks what character the player wants to be
		mov eax, number ; Gets the text for number
		call print_string
		call print_nl
		mov eax, options ; Gets the text for options
		call print_string
		call print_nl
		mov eax, choice ; Gets the text for choice
		call print_string
		call read_int ; Gets the answer
		mov [P], eax ; Changes P to answer
	check: ; Checks to make sure it is correct
		mov ecx, 1
		cmp ecx, eax ; Checks if it equals one
		je done ; Jumps ahead if so
		mov ebx, 2
		cmp ebx, eax ; Checks if it equals two
		je done ; Jumps ahead if so
		jmp player_choice ; Jumps back to the start if neither is true
	done: ; Used to skip ahead


	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable.
	mov		DWORD [SEED], 31
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

		; Position check logic
		push		eax		; save our location
		m_check:
		cmp		BYTE [eax], MYSTERY_CHAR
		jne		w_check
			mov		BYTE [eax], BLANK_CHAR
			call	is_mystery_square
		pop		eax		; restore location
		w_check:
		cmp		BYTE [eax], WALL_CHAR
		jne		valid_move
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
		layout_one: ; Used to specify that this is the first layout
			; Creates the first wall (| )
			mov ecx, 5 ; start y value
			mov edx, 10
			mov [Y], edx ; end y + 1
			mov edx, 10
			mov [X], edx ; x value
			call make_vertical

			;  Creates the second wall ( |)
			mov ecx, 5 ; start y value
			mov edx, 10
            mov [Y], edx ; end y + 1
			mov edx, 25
            mov [X], edx ; x value
            call make_vertical

			;  Creates the third wall ( _ )
			mov ecx, 10 ; start x value
			mov edx, 10
			mov [Y], edx ; y value
			mov edx, 26
			mov [X], edx ; end x + 1
			call make_horizontal

	call add_mystery_blocks

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

	mov eax, [NUM_MYSTERY_BLOCKS]
	cmp eax, 0
	je end_game 

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

	mov eax, current_score  ; load eax with current score message
	call print_string  ; display current score message
	mov eax, [score]  ; load current score into eax
	call print_int  ; display current score
	call print_nl  ; print newline

	mov eax, current_coins  ; load eax with current coins message
	call print_string  ; display current coins message
	mov eax, [num_coins]  ; load number of coins into eax
	call print_int  ; print number of coins
	call print_nl  ; print newline
	call print_nl  ; print newline

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
				mov eax, [P] ; Checks P value
				cmp eax, 1 ; Compares it to 1
				je one_player ; If equal jump to one_player
				cmp eax, 2 ; Compares it to 2
				je two_player ; If equal jump to two_player
				one_player: ; Pushes O as the image for the player
					push	PLAYER_ONE
					call	putchar
					add	esp, 4
					jmp	print_end
				two_player: ; Pushes X as the image for the player
					push	PLAYER_TWO
					call	putchar
					add	esp, 4
					jmp	print_end
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
	
	; Subprogram for making a vertical wall
	make_vertical:
        	mov eax, ecx ; Starting point
        	mov ebx, WIDTH
        	mul ebx
        	add eax, [X] ; How far the wall is
        	mov BYTE [board + eax], WALL_CHAR
        	inc ecx
        	cmp ecx, [Y]     ; end y+1
		jne make_vertical
		ret

	; Subprogram for making a horizontal wall
	make_horizontal:
		mov eax, [Y] ; Starting point
		mov ebx, WIDTH
		mul ebx
		add eax, ecx ; How far the wall is
		mov BYTE [board + eax], WALL_CHAR
		inc ecx
		cmp ecx, [X]	; end x+1
		jne make_horizontal
		ret


	; ###################################################################
	; Subroutine: add_random_blocks
	; Description:
	;   Add MYSTERY_CHAR blocks to the gameboard, avoiding WALL_CHAR cells.
	;   NUM_MYSTERY_BLOCKS is calculated as (WIDTH * HEIGHT) / 100.
	;   This calculation should equal 1% of the board area.
	; Inputs:
	;   Gameboard dimensions: WIDTH, HEIGHT.
	;   Block index: EBX (changes during the loop).
	; Outputs:
	;   MYSTERY_CHAR blocks are placed in pseudo-random positions.

add_mystery_blocks:
    ; Calculate 1% of the board area (WIDTH * HEIGHT) / 100
    mov     eax, WIDTH
    mov     ecx, HEIGHT
    mul     ecx                  ; eax = WIDTH * HEIGHT
	mov		[BAREA], eax
    xor     edx, edx
    mov     ecx, 100
    div     ecx                  ; eax = (WIDTH * HEIGHT) / 100
    mov     ebx, eax             ; ebx = NUM_MYSTERY_BLOCKS (count of mystery blocks to place)
	mov [NUM_MYSTERY_BLOCKS], ebx  ; load value of ebx into NUM_MYSTERY_BLOCKS

mystery_block_loop:
    cmp     ebx, 0
    je      mystery_blocks_done ; Exit if all blocks are placed

    ; Generate a random position
    push    ebx                 ; Save EBX counter
    call    random_position_generator
    pop     ebx                 ; Restore EBX counter

    ; Call verification_check to ensure the spot is valid (not a wall or non-empty)
    call    verification_check

    mov     eax, [R]            ; Load the random position from R
    ; Place MYSTERY_CHAR
    mov     BYTE [board + eax], MYSTERY_CHAR

    ; Decrement block counter only if a block is placed
    dec     ebx

skip_placement:
    jmp     mystery_block_loop

mystery_blocks_done:
    ret

verification_check:
    ; Load the random position
    mov     eax, [R]            ; Get the random position (already calculated)
    mov     al, [board + eax]   ; Load the character at that position

    cmp     al, WALL_CHAR       ; Is it a wall?
	add		[SEED], eax
    je      retry_random        ; If yes, retry the random position generation

    cmp     al, BLANK_CHAR      ; Is it a blank space?
	sub		[SEED], eax
    jne     retry_random        ; If not, retry the random position generation

    ; If it's valid (blank space), return
    ret

retry_random:
    ; Recurse to generate a new random position
    call    random_position_generator
    ret

;##########################################################################

; ##### Handle Mystery square #####
is_mystery_square:
    ; Handle Mystery Square (Replace '?' with BLANK_CHAR)
    ; We already know the player's position is [xpos], [ypos], so we convert to the 1D board index

	mov eax, [NUM_MYSTERY_BLOCKS]  ; load number of mystery blocks into eax
	dec eax					       ; decrement eax (num of mystery blocks)
	mov [NUM_MYSTERY_BLOCKS], eax  ; store updated value of eax back into mystery blocks variable

	call	render
	; Reload position and Generate a pseudo-random number based on xpos and ypos like in the board_init to place random.
	mov     eax, DWORD [xpos]        ; Load xpos
	mov     ebx, DWORD [ypos]        ; Load ypos
	add     eax, ebx                 ; Combine positions to create a unique block index
	mov     ecx, [SEED]              ; Use a seed as a multiplier
	mul     ecx                      ; eax = (xpos + ypos) * SEED
	xor     edx, edx
	mov     ecx, [BAREA]
	mul     ecx         	         ; ecx = WIDTH * HEIGHT
	xor		edx, edx
	div     ecx                      ; edx = (block index * SEED) % area
	mov     eax, edx                 ; eax = random value in range 0–(WIDTH * HEIGHT - 1)

	; Scale to desired range (0–99)
	xor     edx, edx
	mov     ecx, 10                 ; Target range is 0–99
	div     ecx                      ; eax = eax % 100

	; Check the result range
	breakpoint:
	cmp     eax, 33					 
	jl      teleport                 ; 0–32: Teleport
	cmp     eax, 66
	jl      bomb                     ; 33-65: Bomb
	jmp     coin					 ; 66-99: Coin

	ret		; failsafe return
; ####### END: Mystery square ########
; ## Adjust the values and add jumps 
; ## to add a bag of coins or add
; ## big point squares, etc.
; ####################################
; ##### MYSTERY BLOCK ACTIONS ########
; ####################################
teleport:
    ; Generate a random position
    sub     [SEED], eax               ; Modify SEED for randomness
    call    random_position_generator
    mov     eax, [R]                  ; Store the result from random_position_generator

    ; Convert the random position (eax) back into x and y coordinates
    mov     ebx, eax                  ; Use eax (random position) to index into the board
    xor     edx, edx                  ; Clear edx for division (since we're using div)

    ; Calculate new xpos (x = pos % WIDTH)
    mov     ecx, WIDTH              ; Load WIDTH
    div     ecx                       ; edx = eax % WIDTH (xpos)
    mov     DWORD [xpos], edx         ; Store the new xpos

    ; Calculate new ypos (y = pos / WIDTH)
    mov     DWORD [ypos], eax         ; Store the new ypos

    ; Now check the new position on the board
    lea     eax, [board + ebx]        ; Get the address of the new position in the board array
    cmp     BYTE [eax], WALL_CHAR     ; Check if it's a wall
    je      teleport                  ; If it's a wall, try another teleport

    ; If it's not a wall, update player position
    mov     esi, DWORD [xpos]         ; Update xpos (column)
    mov     edi, DWORD [ypos]         ; Update ypos (row)

    jmp     game_loop                 ; Continue the game loop

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
bomb:
    ; Bomb explodes in a + (2 up/down, 4 left/right) and clears the spaces
    ; Player moves to bomb's position.

    mov     esi, DWORD [xpos]         ; Store xpos in esi
    mov     edi, DWORD [ypos]         ; Store ypos in edi

    ; Clear vertical area (2 up, 2 down) around ypos
    ; Loop over the vertical range (ypos - 2) to (ypos + 2)
    mov     ecx, edi                  ; Start from ypos (row)
    sub     ecx, 2                    ; Set ECX to ypos - 2 (start of vertical loop)
    mov     ebx, edi                  ; Store original ypos in ebx for comparison
    add     ebx, 2                    ; Set ebx to ypos + 2 (end of vertical loop)

bomb_y_loop:
    cmp     ecx, ebx                  ; Check if we've reached ypos + 2
    jg      bomb_x_loop               ; If we have, jump to the horizontal loop

    ; Check if current row is within bounds (ypos - 2 to ypos + 2)
    cmp     ecx, 0                    ; Check if row is above board (ypos - 2 < 0)
    jl      skip_y_loop               ; If out of bounds, skip
    cmp     ecx, HEIGHT              ; Check if row is below board (ypos + 2 >= HEIGHT)
    jge     skip_y_loop               ; If out of bounds, skip

    ; Clear horizontal area (4 left, 4 right) around xpos
    ; Loop over the horizontal range (xpos - 4) to (xpos + 4)
    mov     eax, esi                  ; Start from xpos (column)
    sub     eax, 4                    ; Set EAX to xpos - 4 (start of horizontal loop)
    mov     edx, esi                  ; Store original xpos in edx for comparison
    add     edx, 4                    ; Set edx to xpos + 4 (end of horizontal loop)

bomb_x_loop:
    cmp     eax, edx                  ; Check if we've reached xpos + 4
    jg      skip_bomb_clear           ; If we have, skip clearing the tiles

    ; Check if current column is within bounds (xpos - 4 to xpos + 4)
    cmp     eax, 0                    ; Check if column is left of the board (xpos - 4 < 0)
    jl      skip_bomb_clear           ; If out of bounds, skip
    cmp     eax, WIDTH                ; Check if column is right of the board (xpos + 4 >= WIDTH)
    jge     skip_bomb_clear           ; If out of bounds, skip

    ; Calculate the address of board[ecx][eax] (break it into two steps)
    ; Step 1: Compute the row offset (ecx * WIDTH)
    mov     ebx, ecx                  ; Store ypos in ebx
    imul    ebx, WIDTH              ; ebx = ypos * WIDTH

    ; Step 2: Add xpos (eax) to get the final address
    add     ebx, eax                  ; ebx = (ypos * WIDTH) + xpos

    ; Now ebx contains the correct offset into the board
    lea     edi, [board + ebx]        ; Calculate the address of the tile

    ; Clear the tile by setting it to BLANK_CHAR
    mov     BYTE [edi], BLANK_CHAR

    inc     eax                       ; Move to the next horizontal tile (increment xpos)
    jmp     bomb_x_loop               ; Repeat for the next tile

skip_bomb_clear:
    inc     ecx                       ; Move to the next vertical tile (increment ypos)
    jmp     bomb_y_loop               ; Repeat for the next row

skip_y_loop:
    ret

coin:
    mov eax, WIDTH
    mul DWORD [ypos]
    add eax, DWORD [xpos]

    ; place a coin
    mov BYTE [board + eax], BLANK_CHAR  ; set a coin with the mystery character

    call update_score  ; update player score
    call update_coins  ; update player coins

    jmp game_loop  ; continue game 


	; ###################################################################
	; Subroutine: random_position_generator
	; Description:
	;   Generate pseudo-random offset using block index and a prime number.
	; Inputs:
	;   EBX = block index (unique for each block)
	; Outputs:
	;   EDX = pseudo-random offset (1D index) within the gameboard area
	; Registers used: EAX, EBX, ECX, ESI, EDX

random_position_generator:
    mov     eax, ebx            ; EAX = block_loop index (parameter)
    mov     esi, [SEED]         ; seed value multiplier
	add		[SEED], esi			; Update to new seed
    mul     esi                 ; EAX = block index * 31
    xor     edx, edx            ; Clear EDX
    mov     ecx, WIDTH          ; ECX = WIDTH (number of columns)
    mul     ecx                 ; EAX = block index * 31 * WIDTH
    add     eax, edx            ; Add any leftover from previous mul
    xor     edx, edx            ; Clear EDX again
    div     ecx                 ; EDX = (block index * 31) % WIDTH

    ; Now EAX contains a "random" value, scale it to [1, 800]
    mov     ecx, [BAREA]        ; Max value for the game board area
    xor     edx, edx            ; Clear EDX for division
    div     ecx                 ; EAX = (random number) / 800 -> Quotient in EAX, Remainder in EDX
    add     edx, 1              ; Add 1 to ensure it's in range [1, 800]

    ; Store the result (random position) in R (or temporary storage)
    mov     [R], edx            ; Store final random position in R
	mov		edx, 0
    ret

; generate 20 coins and call a coin generation loop
generate_coins:
	push ebp
	mov ebp, esp

	mov eax, 20  ; load number of coins to generate into eax
	mov [num_coins], eax  ; store initial number of coins in num_coins variable

	call coin_creation_loop  ; call loop to place coins in random positions

; generate coins in random positions
coin_creation_loop:
	push ebp
	mov ebp, esp

	mov ecx, 20  ; 20 will be the loop counter

coin_loop_start:
	cmp ecx, 0  ; compare ecx (stores number of coins) with 0
	je coin_loop_end  ; if ecx = 0 end loop because all 20 coins have been placed

	call random_position_generator  ; generate a random position for each coin

	mov eax, [R]  ; load a random index into eax
	mov bl, [board + eax]  ; load the value at that index

	cmp bl, BLANK_CHAR  ; see if bl is a blank space
	jne coin_loop_start  ; if it's not a blank space, keep looking for one 

	mov byte [board + eax], '?'  ; place a coin and mark position with a question mark

	dec ecx  ; decrement the loop counter

coin_loop_end:
	pop ebp
	ret

; add one to the score each time a coin is obtained
update_score:
	push ebp
	mov ebp, esp

	mov eax, [score]  ; load current score into eax
	add eax, 15  ; add 15 points for each coin to score

	mov [score], eax  ; update score

	pop ebp
	ret

; add a coin to the total number of coins each time the coin's position is visited
update_coins:
	push ebp
	mov ebp, esp

	mov eax, [num_coins]  ; load current number of coins into eax
	add eax, 1  ; increment number of coins
	mov [num_coins], eax  ; update the number of coins variable

	pop ebp
	ret

; displays "GAME OVER" when the player has hit all mystery characters
end_game:
	end_game:
	push ebp
	mov ebp, esp

	mov eax, game_over  ; load eax with game over message
	call print_string   ; print game over message
	call print_nl

	call raw_mode_off    ; exit game

	mov eax, 0
	mov esp, ebp
	pop ebp

	ret
