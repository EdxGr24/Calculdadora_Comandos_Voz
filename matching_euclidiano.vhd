-- euclidean_matcher.vhd actualizado para usar plantillas_pkg
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.plantillas_pkg.all;  -- 

entity matching_euclidiano is
    port (
        CLK_SYS         : in  std_logic;
        RST             : in  std_logic;
        magnitud_dato   : in  std_logic_vector(15 downto 0);
        magnitud_bin    : in  integer range 0 to 15;
        magnitud_valido : in  std_logic;
        espectro_listo  : in  std_logic;
        id_comando      : out integer range 0 to 13;
        comando_valido  : out std_logic
    );
end entity matching_euclidiano;

architecture rtl of matching_euclidiano is

    constant NUM_PLANTILLAS : integer := 14;
    constant NUM_COEFS      : integer := 16;

    -- Espectro usa unsigned internamente
    type t_espectro is array(0 to NUM_COEFS-1)
        of unsigned(15 downto 0);

    signal espectro_actual : t_espectro := (others => (others => '0'));

    signal cnt_plantilla : integer range 0 to NUM_PLANTILLAS-1 := 0;
    signal cnt_coef      : integer range 0 to NUM_COEFS-1      := 0;
    signal dist_acum     : unsigned(31 downto 0) := (others => '0');
    signal dist_minima   : unsigned(31 downto 0) := (others => '1');
    signal id_minimo     : integer range 0 to NUM_PLANTILLAS-1 := 0;

    type t_estado is (ESPERANDO, COMPARANDO, EVALUANDO, TERMINADO);
    signal estado : t_estado := ESPERANDO;

begin

    -- Proceso 1: capturar espectro
    proc_captura: process(CLK_SYS)
    begin
        if rising_edge(CLK_SYS) then
            if RST = '1' then
                espectro_actual <= (others => (others => '0'));
            elsif magnitud_valido = '1' then
                espectro_actual(magnitud_bin) <= unsigned(magnitud_dato);
            end if;
        end if;
    end process proc_captura;

    -- Proceso 2: matching euclidiano
    proc_matching: process(CLK_SYS)
        variable diferencia    : signed(16 downto 0);
        variable coef_plantilla: integer;
        variable cuadrado      : unsigned(31 downto 0);
    begin
        if rising_edge(CLK_SYS) then
            if RST = '1' then
                cnt_plantilla  <= 0;
                cnt_coef       <= 0;
                dist_acum      <= (others => '0');
                dist_minima    <= (others => '1');
                id_minimo      <= 0;
                id_comando     <= 0;
                comando_valido <= '0';
                estado         <= ESPERANDO;

            else
                comando_valido <= '0';

                case estado is

                    when ESPERANDO =>
                        if espectro_listo = '1' then
                            cnt_plantilla <= 0;
                            cnt_coef      <= 0;
                            dist_acum     <= (others => '0');
                            dist_minima   <= (others => '1');
                            estado        <= COMPARANDO;
                        end if;

                    when COMPARANDO =>
                        -- Leer coeficiente desde el paquete
                        -- PLANTILLAS es array de integer → convertir a unsigned
                        coef_plantilla := PLANTILLAS(cnt_plantilla)(cnt_coef);

                        -- Diferencia con signo extendido a 17 bits
                        diferencia :=
                            signed('0' & espectro_actual(cnt_coef)) -
                            signed(to_unsigned(coef_plantilla, 16));

                        -- Cuadrado
                        cuadrado := resize(
                            unsigned(abs(diferencia)) *
                            unsigned(abs(diferencia)), 32);

                        -- Acumular
                        dist_acum <= dist_acum + cuadrado;

                        if cnt_coef = NUM_COEFS - 1 then
                            cnt_coef <= 0;
                            estado   <= EVALUANDO;
                        else
                            cnt_coef <= cnt_coef + 1;
                        end if;

                    when EVALUANDO =>
                        if dist_acum < dist_minima then
                            dist_minima <= dist_acum;
                            id_minimo   <= cnt_plantilla;
                        end if;

                        dist_acum <= (others => '0');

                        if cnt_plantilla = NUM_PLANTILLAS - 1 then
                            estado <= TERMINADO;
                        else
                            cnt_plantilla <= cnt_plantilla + 1;
                            estado        <= COMPARANDO;
                        end if;

                    when TERMINADO =>
                        id_comando     <= id_minimo;
                        comando_valido <= '1';
                        cnt_plantilla  <= 0;
                        dist_minima    <= (others => '1');
                        estado         <= ESPERANDO;

                end case;
            end if;
        end if;
    end process proc_matching;

end architecture rtl;