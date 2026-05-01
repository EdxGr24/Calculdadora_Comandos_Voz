--controlador_i2s.vhd
-- Controlador I2S para micrófono MEMS INMP441
-- Genera SCK Y WS, lee SD, entrega una muestra de 16 bits

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity controlador_i2s is
    generic (
        DIVISOR_SCK : integer := 13
    );
    
    port (
        CLK_SYS : in std_logic; -- CLK de la FPGA
        RST     : in std_logic;
        -- Pines hacia el micrófono
        SD      : in std_logic;
        SCK     : out std_logic;
        WS      : out std_logic;
        -- Salida hacia el pipeline DSP
        dato_audio  : out std_logic_vector(15 downto 0);
        dato_valido : out std_logic
    );

end controlador_i2s; 

 architecture rtl of controlador_i2s is

-- Generador de SCK
signal contador_sck  : integer range 0 to DIVISOR_SCK-1 := 0;
signal registro_sck  : std_logic := '0';

-- Generador de WS
signal contador_ws   : integer range 0 to 63 := 0;
signal registro_ws   : std_logic := '0';

-- Captura de bits
signal registro_desp : std_logic_vector(31 downto 0) := (others => '0');
signal indice_bit    : integer range 0 to 31 := 0;

-- Flanco de SCK
signal sck_anterior  :std_logic := '0';

begin 

-- Proceso: Generador de SCK / Divisor de Frecuencia
proc_sck : process(CLK_SYS)
begin
    if rising_edge(CLK_SYS) then
        if RST = '1' then   
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

-- Proceso: Captura de Datos y generador de WS
proc_captura: process(CLK_SYS)
begin
    if rising_edge(CLK_SYS) then
        if RST = '0' then
            sck_anterior <= '0';
            contador_ws  <= 0;
            registro_ws  <= '0';
            indice_bit   <= 0;
            registro_desp <= (others => '0');
            dato_valido  <= '0';
        else    
            sck_anterior <= registro_sck;
            dato_valido  <= '0';
            
            -- Detección flanco ascendente de SCK
            if sck_anterior = '0' and registro_sck = '1' then
                -- Captura bit MSB primero
                registro_desp(31 - indice_bit) <= SD;
                
                if indice_bit = 31 then
                    indice_bit <= 0;
                    registro_ws <= not registro_ws;

                    -- Canal izquierdo completado
                    if registro_ws = '0' then
                        dato_audio <= registro_desp(31 downto 16);
                        dato_valido <= '1';
                    end if;
                else
                    indice_bit <= indice_bit + 1;
                end if;
            end if;
        end if;
    end if;
end process proc_captura;

WS <= registro_ws;

end architecture rtl;