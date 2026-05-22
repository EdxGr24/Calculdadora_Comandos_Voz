-- uart_tx.vhd
-- Transmisor UART para comunicación FPGA → ESP32
-- Acumula 5 IDs del matching, construye trama de 3 bytes
-- y los transmite a 9600 bps 8N1


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    generic (
        -- Ciclos de reloj por bit UART
        -- CLK=27MHz, baud=9600 → 27,000,000/9600 = 2812
        CICLOS_POR_BIT : integer := 2812
    );
    port (
        CLK_SYS        : in  std_logic;
        RST            : in  std_logic;

        -- Entrada desde matching euclidiano
        id_comando     : in  integer range 0 to 13;
        comando_valido : in  std_logic;

        -- Salida física hacia ESP32 GPIO16
        uart_tx_pin    : out std_logic;

        -- Indicadores de estado (opcionales, útiles para debug)
        listo          : out std_logic;  -- '1' cuando puede recibir nuevo ID
        transmitiendo  : out std_logic   -- '1' mientras envía trama
    );
end entity uart_tx;

architecture rtl of uart_tx is

    -- ─── Tipos ───────────────────────────────────────
    type t_trama is array(0 to 2) of std_logic_vector(7 downto 0);

    -- ─── Máquina de estados principal ────────────────
    type t_estado_principal is (
        ESPERANDO_D1_NUM1,   -- esperando primer dígito de NUM1
        ESPERANDO_D2_NUM1,   -- esperando segundo dígito de NUM1
        ESPERANDO_OP,        -- esperando operador
        ESPERANDO_D1_NUM2,   -- esperando primer dígito de NUM2
        ESPERANDO_D2_NUM2,   -- esperando segundo dígito de NUM2
        ENVIANDO_TRAMA       -- transmitiendo los 3 bytes por UART
    );

    -- ─── Máquina de estados UART 
    type t_estado_uart is (
        UART_IDLE,      -- línea en reposo
        UART_START,     -- bit de inicio
        UART_DATA,      -- 8 bits de datos
        UART_STOP       -- bit de parada
    );

    -- ─── Señales principales 
    signal estado_principal : t_estado_principal := ESPERANDO_D1_NUM1;
    signal estado_uart      : t_estado_uart      := UART_IDLE;

    -- Dígitos capturados
    signal d1_num1 : integer range 0 to 9 := 0;
    signal d2_num1 : integer range 0 to 9 := 0;
    signal d1_num2 : integer range 0 to 9 := 0;
    signal d2_num2 : integer range 0 to 9 := 0;

    -- Trama de 3 bytes lista para enviar
    signal trama        : t_trama := (others => (others => '0'));
    signal byte_actual  : integer range 0 to 2 := 0;

    -- Señales del transmisor UART serie
    signal contador_baud : integer range 0 to CICLOS_POR_BIT-1 := 0;
    signal contador_bits : integer range 0 to 7 := 0;
    signal registro_tx   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_inicio     : std_logic := '0';  -- pulso para iniciar TX de un byte

    -- ─── Función: convierte ID de operador a byte ASCII ──
    function id_a_operador(id : integer) return std_logic_vector is
    begin
        case id is
            when 10    => return x"2B";  -- '+' mas
            when 11    => return x"2D";  -- '-' menos
            when 12    => return x"2A";  -- '*' por
            when 13    => return x"2F";  -- '/' entre
            when others => return x"2B"; -- default '+'
        end case;
    end function;

begin

    -- Proceso 1: acumulador de IDs y constructor de trama
    -- Recibe IDs del matching uno a uno y cuando tiene
    -- los 5 necesarios construye y lanza la trama UART
    -- 
    proc_acumulador: process(CLK_SYS)
        variable num1_val : integer range 0 to 99;
        variable num2_val : integer range 0 to 99;
    begin
        if rising_edge(CLK_SYS) then
            if RST = '1' then
                estado_principal <= ESPERANDO_D1_NUM1;
                d1_num1          <= 0;
                d2_num1          <= 0;
                d1_num2          <= 0;
                d2_num2          <= 0;
                trama            <= (others => (others => '0'));
                tx_inicio        <= '0';
                listo            <= '1';
                transmitiendo    <= '0';

            else
                tx_inicio <= '0';  -- pulso de un ciclo

                case estado_principal is

                    -- ── Esperar primer dígito de NUM1 
                    when ESPERANDO_D1_NUM1 =>
                        listo <= '1';
                        if comando_valido = '1' and id_comando <= 9 then
                            d1_num1          <= id_comando;
                            estado_principal <= ESPERANDO_D2_NUM1;
                        end if;

                    -- ── Esperar segundo dígito de NUM1 
                    when ESPERANDO_D2_NUM1 =>
                        if comando_valido = '1' and id_comando <= 9 then
                            d2_num1          <= id_comando;
                            estado_principal <= ESPERANDO_OP;
                        end if;

                    -- ── Esperar operador 
                    when ESPERANDO_OP =>
                        if comando_valido = '1' and
                           id_comando >= 10 and id_comando <= 13 then
                            -- Guardar operador como byte ASCII en trama[1]
                            trama(1)         <= id_a_operador(id_comando);
                            estado_principal <= ESPERANDO_D1_NUM2;
                        end if;

                    -- ── Esperar primer dígito de NUM2 ────────
                    when ESPERANDO_D1_NUM2 =>
                        if comando_valido = '1' and id_comando <= 9 then
                            d1_num2          <= id_comando;
                            estado_principal <= ESPERANDO_D2_NUM2;
                        end if;

                    -- ── Esperar segundo dígito de NUM2 ───────
                    when ESPERANDO_D2_NUM2 =>
                        if comando_valido = '1' and id_comando <= 9 then
                            d2_num2 <= id_comando;

                            -- Construir NUM1 y NUM2 como valores 0-99
                            num1_val := d1_num1 * 10 + d2_num1;
                            num2_val := d1_num2 * 10 + id_comando;

                            -- Guardar en trama
                            trama(0) <= std_logic_vector(
                                        to_unsigned(num1_val, 8));
                            trama(2) <= std_logic_vector(
                                        to_unsigned(num2_val, 8));

                            -- Iniciar transmisión
                            listo            <= '0';
                            transmitiendo    <= '1';
                            byte_actual      <= 0;
                            tx_inicio        <= '1';
                            estado_principal <= ENVIANDO_TRAMA;
                        end if;

                    -- ── Enviando trama 
                    -- Espera a que el transmisor UART termine
                    -- cada byte y lanza el siguiente
                    when ENVIANDO_TRAMA =>
                        if estado_uart = UART_IDLE and
                           tx_inicio = '0' then
                            if byte_actual < 2 then
                                -- Lanzar siguiente byte
                                byte_actual <= byte_actual + 1;
                                tx_inicio   <= '1';
                            else
                                -- Los 3 bytes fueron enviados
                                transmitiendo    <= '0';
                                estado_principal <= ESPERANDO_D1_NUM1;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process proc_acumulador;


    -- Proceso 2: transmisor UART serie
    -- Convierte un byte en bits serie a 9600 bps
    -- Protocolo: 1 start bit + 8 data bits + 1 stop bit
   
    proc_uart: process(CLK_SYS)
    begin
        if rising_edge(CLK_SYS) then
            if RST = '1' then
                estado_uart   <= UART_IDLE;
                uart_tx_pin   <= '1';  -- línea en reposo = alto
                contador_baud <= 0;
                contador_bits <= 0;
                registro_tx   <= (others => '0');

            else
                case estado_uart is

                    -- ── IDLE: esperando orden de transmisión 
                    when UART_IDLE =>
                        uart_tx_pin <= '1';  -- reposo
                        if tx_inicio = '1' then
                            -- Cargar byte a transmitir
                            registro_tx   <= trama(byte_actual);
                            contador_baud <= 0;
                            estado_uart   <= UART_START;
                        end if;

                    -- ── START: bit de inicio (0) 
                    -- Dura exactamente CICLOS_POR_BIT ciclos
                    when UART_START =>
                        uart_tx_pin <= '0';  -- start bit = bajo
                        if contador_baud = CICLOS_POR_BIT - 1 then
                            contador_baud <= 0;
                            contador_bits <= 0;
                            estado_uart   <= UART_DATA;
                        else
                            contador_baud <= contador_baud + 1;
                        end if;

                    -- ── DATA: 8 bits de datos (LSB primero) 
                    when UART_DATA =>
                        uart_tx_pin <= registro_tx(contador_bits);
                        if contador_baud = CICLOS_POR_BIT - 1 then
                            contador_baud <= 0;
                            if contador_bits = 7 then
                                estado_uart <= UART_STOP;
                            else
                                contador_bits <= contador_bits + 1;
                            end if;
                        else
                            contador_baud <= contador_baud + 1;
                        end if;

                    -- ── STOP: bit de parada (1) 
                    when UART_STOP =>
                        uart_tx_pin <= '1';  -- stop bit = alto
                        if contador_baud = CICLOS_POR_BIT - 1 then
                            contador_baud <= 0;
                            estado_uart   <= UART_IDLE;
                        else
                            contador_baud <= contador_baud + 1;
                        end if;

                end case;
            end if;
        end if;
    end process proc_uart;

end architecture rtl;