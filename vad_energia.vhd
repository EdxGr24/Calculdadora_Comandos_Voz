
-- Detector de actividad de voz por umbral de energía
-- Ventana de 20ms a 16kHz = 320 muestras


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vad_energia is
    generic (
        -- Número de muestras por ventana
        -- 20ms × 16000 Hz = 320 muestras
        TAM_VENTANA : integer := 320;

        -- Umbral de energía para detectar voz
        -- Ajustar según nivel de ruido del ambiente
        -- Valor en unidades de energía acumulada Q
        UMBRAL_ENERGIA : unsigned(31 downto 0) :=
            x"0F000000"
    );
    port (
        CLK_SYS        : in  std_logic;
        RST            : in  std_logic;

        -- Entrada desde filtro FIR
        entrada_dato   : in  std_logic_vector(15 downto 0);
        entrada_valido : in  std_logic;

        -- Salida hacia FFT
        salida_dato    : out std_logic_vector(15 downto 0);
        salida_valido  : out std_logic;

        -- Indicador de voz activa 
        voz_detectada  : out std_logic
    );
end entity vad_energia;

architecture rtl of vad_energia is

    -- Acumulador de energía de la ventana actual
    signal energia_acum  : unsigned(31 downto 0) := (others => '0');

    -- Contador de muestras en la ventana
    signal cnt_ventana   : integer range 0 to TAM_VENTANA-1 := 0;

    -- Estado de actividad de voz
    signal voz_activa    : std_logic := '0';

    -- Muestra actual con signo para calcular cuadrado
    signal muestra_sig   : signed(15 downto 0) := (others => '0');

begin

    proc_vad: process(CLK_SYS)
        variable cuadrado : unsigned(31 downto 0);
        variable muestra_abs : unsigned(15 downto 0);
    begin
        if rising_edge(CLK_SYS) then
            if RST = '1' then
                energia_acum  <= (others => '0');
                cnt_ventana   <= 0;
                voz_activa    <= '0';
                salida_valido <= '0';
                salida_dato   <= (others => '0');
                voz_detectada <= '0';

            else
                salida_valido <= '0';

                if entrada_valido = '1' then
                    muestra_sig <= signed(entrada_dato);

                    -- Calcular |muestra|² y acumular
                    -- Usar valor absoluto para evitar overflow
                    -- en la multiplicación
                    if signed(entrada_dato) < 0 then
                        muestra_abs := unsigned(
                            -signed(entrada_dato));
                    else
                        muestra_abs := unsigned(entrada_dato);
                    end if;

                    -- Cuadrado de 16 bits → 32 bits
                    cuadrado := muestra_abs * muestra_abs;

                    -- Acumular energía (con saturación)
                    if energia_acum + cuadrado < energia_acum then
                        energia_acum <= (others => '1'); -- saturar
                    else
                        energia_acum <= energia_acum + cuadrado;
                    end if;

                    -- Fin de ventana de 320 muestras
                    if cnt_ventana = TAM_VENTANA - 1 then
                        cnt_ventana <= 0;

                        -- Comparar energía acumulada con umbral
                        if energia_acum >= UMBRAL_ENERGIA then
                            voz_activa    <= '1';
                            voz_detectada <= '1';
                        else
                            voz_activa    <= '0';
                            voz_detectada <= '0';
                        end if;

                        -- Reiniciar acumulador
                        energia_acum <= (others => '0');
                    else
                        cnt_ventana <= cnt_ventana + 1;
                    end if;

                    -- Pasar muestra hacia FFT solo si hay voz
                    if voz_activa = '1' then
                        salida_dato   <= entrada_dato;
                        salida_valido <= '1';
                    end if;

                end if;
            end if;
        end if;
    end process proc_vad;

end architecture rtl;