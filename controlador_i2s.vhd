-- controlador_i2s.vhd
-- Controlador I2S para micrófono MEMS INMP441
-- Genera SCK y WS, lee SD, entrega muestras de 16 bits
-- RST activo-alto en todos los procesos (el top_level invierte el botón físico)
-- VHDL-2008

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity controlador_i2s is
    generic (
        DIVISOR_SCK : integer := 13
    );
    port (
        CLK_SYS     : in  std_logic;
        RST         : in  std_logic;  -- activo-alto (lo invierte el top_level)
        -- Pines físicos hacia el INMP441
        SD          : in  std_logic;
        SCK         : out std_logic;
        WS          : out std_logic;
        -- Salida hacia el pipeline DSP
        dato_audio  : out std_logic_vector(15 downto 0);
        dato_valido : out std_logic
    );
end entity controlador_i2s;

architecture rtl of controlador_i2s is

    -- Generador de SCK
    signal contador_sck  : integer range 0 to DIVISOR_SCK-1 := 0;
    signal registro_sck  : std_logic := '0';

    -- Generador de WS
    signal registro_ws   : std_logic := '0';

    -- Captura de bits
    signal registro_desp : std_logic_vector(31 downto 0) := (others => '0');
    signal indice_bit    : integer range 0 to 31 := 0;

    -- Detección de flanco de SCK
    signal sck_anterior  : std_logic := '0';

begin

    -- ─────────────────────────────────────────────────
    -- Proceso 1: Generador de SCK
    -- Divide CLK_SYS por DIVISOR_SCK para producir SCK
    -- Con CLK=27MHz y DIVISOR=13: SCK ≈ 1.038 MHz
    -- ─────────────────────────────────────────────────
    proc_sck: process(CLK_SYS)
    begin
        if rising_edge(CLK_SYS) then
            if RST = '1' then           -- RST activo-alto
                contador_sck <= 0;
                registro_sck <= '0';
            else
                if contador_sck = DIVISOR_SCK - 1 then
                    contador_sck <= 0;
                    registro_sck <= not registro_sck;
                else
                    contador_sck <= contador_sck + 1;
                end if;
            end if;
        end if;
    end process proc_sck;

    SCK <= registro_sck;

    -- ─────────────────────────────────────────────────
    -- Proceso 2: Captura de datos y generador de WS
    -- Detecta flanco ascendente de SCK y captura SD
    -- El INMP441 actualiza SD en flanco descendente
    -- → capturamos en flanco ascendente (dato estable)
    -- ─────────────────────────────────────────────────
    proc_captura: process(CLK_SYS)
    begin
        if rising_edge(CLK_SYS) then
            if RST = '1' then           -- RST activo-alto (igual que proc_sck)
                sck_anterior  <= '0';
                registro_ws   <= '0';
                indice_bit    <= 0;
                registro_desp <= (others => '0');
                dato_audio    <= (others => '0');
                dato_valido   <= '0';
            else
                sck_anterior <= registro_sck;
                dato_valido  <= '0';    -- por defecto, sin dato nuevo

                -- Detectar flanco ascendente de SCK
                if sck_anterior = '0' and registro_sck = '1' then

                    -- Capturar bit en posición MSB-first
                    registro_desp(31 - indice_bit) <= SD;

                    if indice_bit = 31 then
                        indice_bit  <= 0;
                        registro_ws <= not registro_ws;

                        -- Canal izquierdo completado (WS='0' antes del toggle)
                        -- El INMP441 solo tiene canal izquierdo
                        if registro_ws = '0' then
                            dato_audio  <= registro_desp(31 downto 16);
                            dato_valido <= '1';
                        end if;
                        -- Canal derecho (registro_ws='1'): ignorar

                    else
                        indice_bit <= indice_bit + 1;
                    end if;

                end if;
            end if;
        end if;
    end process proc_captura;

    WS <= registro_ws;

end architecture rtl;