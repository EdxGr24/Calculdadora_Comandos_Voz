-- top_level.vhd
-- Entidad maestra del proyecto — conecta todos los módulos
-- FPGA Sipeed Tang Primer 25K
-- VHDL-2008
-- Corregido: RST activo-bajo, LEDs activo-bajo

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_level is
    port (
        -- Reloj del sistema (27 MHz oscilador Tang Primer 25K)
        CLK_SYS     : in  std_logic;

        -- Reset activo BAJO (botón en la FPGA)
        -- '0' = reset activo, '1' = operación normal
        RST         : in  std_logic;

        -- Pines del micrófono INMP441
        MIC_SCK     : out std_logic;
        MIC_WS      : out std_logic;
        MIC_SD      : in  std_logic;

        -- Pin UART hacia ESP32 GPIO16
        PIN_UART_TX : out std_logic;

        -- LEDs de debug (activo-bajo: '0' = encendido)
        LED_VOZ     : out std_logic;
        LED_TX      : out std_logic
    );
end entity top_level;

architecture rtl of top_level is

    -- ─── RST interno activo-alto ──────────────────────
    -- El botón físico es activo-bajo ('0'=presionado=reset)
    -- Los módulos internos están escritos con RST activo-alto
    -- Esta señal invierte la lógica del botón
    signal rst_interno : std_logic;

    -- ─── Declaración de componentes ──────────────────

    component controlador_i2s is
        generic (DIVISOR_SCK : integer := 13);
        port (
            CLK_SYS     : in  std_logic;
            RST         : in  std_logic;
            SCK         : out std_logic;
            WS          : out std_logic;
            SD          : in  std_logic;
            dato_audio  : out std_logic_vector(15 downto 0);
            dato_valido : out std_logic
        );
    end component;

    component filtro_fir is
        port (
            CLK_SYS        : in  std_logic;
            RST            : in  std_logic;
            entrada_dato   : in  std_logic_vector(15 downto 0);
            entrada_valido : in  std_logic;
            salida_dato    : out std_logic_vector(15 downto 0);
            salida_valido  : out std_logic
        );
    end component;

    component vad_energia is
        generic (
            TAM_VENTANA    : integer  := 320;
            UMBRAL_ENERGIA : unsigned(31 downto 0) := x"0F000000"
        );
        port (
            CLK_SYS        : in  std_logic;
            RST            : in  std_logic;
            entrada_dato   : in  std_logic_vector(15 downto 0);
            entrada_valido : in  std_logic;
            salida_dato    : out std_logic_vector(15 downto 0);
            salida_valido  : out std_logic;
            voz_detectada  : out std_logic
        );
    end component;

    component fft_truncada is
        port (
            CLK_SYS        : in  std_logic;
            RST            : in  std_logic;
            entrada_dato   : in  std_logic_vector(15 downto 0);
            entrada_valido : in  std_logic;
            magnitud_dato  : out std_logic_vector(15 downto 0);
            magnitud_bin   : out integer range 0 to 15;
            magnitud_valido: out std_logic;
            espectro_listo : out std_logic
        );
    end component;

    component matching_euclidiano is
        port (
            CLK_SYS        : in  std_logic;
            RST            : in  std_logic;
            magnitud_dato  : in  std_logic_vector(15 downto 0);
            magnitud_bin   : in  integer range 0 to 15;
            magnitud_valido: in  std_logic;
            espectro_listo : in  std_logic;
            id_comando     : out integer range 0 to 13;
            comando_valido : out std_logic
        );
    end component;

    component uart_tx is
        generic (CICLOS_POR_BIT : integer := 2812);
        port (
            CLK_SYS        : in  std_logic;
            RST            : in  std_logic;
            id_comando     : in  integer range 0 to 13;
            comando_valido : in  std_logic;
            uart_tx_pin    : out std_logic;
            listo          : out std_logic;
            transmitiendo  : out std_logic
        );
    end component;

    -- ─── Señales internas entre módulos ──────────────

    signal i2s_dato       : std_logic_vector(15 downto 0);
    signal i2s_valido     : std_logic;

    signal fir_dato       : std_logic_vector(15 downto 0);
    signal fir_valido     : std_logic;

    signal vad_dato       : std_logic_vector(15 downto 0);
    signal vad_valido     : std_logic;
    signal voz_activa     : std_logic;

    signal fft_mag_dato   : std_logic_vector(15 downto 0);
    signal fft_mag_bin    : integer range 0 to 15;
    signal fft_mag_valido : std_logic;
    signal fft_listo      : std_logic;

    signal match_id_cmd   : integer range 0 to 13;
    signal match_valido   : std_logic;

    signal uart_listo     : std_logic;
    signal uart_tx_activo : std_logic;

begin

    -- ─── Inversión del reset ──────────────────────────
    -- Botón físico: '0'=presionado=reset, '1'=suelto=normal
    -- Módulos internos: '1'=reset, '0'=normal
    rst_interno <= not RST;

    -- ─── Instancias de módulos ────────────────────────

    inst_i2s: controlador_i2s
        generic map (DIVISOR_SCK => 13)
        port map (
            CLK_SYS     => CLK_SYS,
            RST         => rst_interno,
            SCK         => MIC_SCK,
            WS          => MIC_WS,
            SD          => MIC_SD,
            dato_audio  => i2s_dato,
            dato_valido => i2s_valido
        );

    inst_fir: filtro_fir
        port map (
            CLK_SYS        => CLK_SYS,
            RST            => rst_interno,
            entrada_dato   => i2s_dato,
            entrada_valido => i2s_valido,
            salida_dato    => fir_dato,
            salida_valido  => fir_valido
        );

    inst_vad: vad_energia
        generic map (
            TAM_VENTANA    => 320,
            UMBRAL_ENERGIA => x"00100000"
        )
        port map (
            CLK_SYS        => CLK_SYS,
            RST            => rst_interno,
            entrada_dato   => fir_dato,
            entrada_valido => fir_valido,
            salida_dato    => vad_dato,
            salida_valido  => vad_valido,
            voz_detectada  => voz_activa
        );

    inst_fft: fft_truncada
        port map (
            CLK_SYS        => CLK_SYS,
            RST            => rst_interno,
            entrada_dato   => vad_dato,
            entrada_valido => vad_valido,
            magnitud_dato  => fft_mag_dato,
            magnitud_bin   => fft_mag_bin,
            magnitud_valido=> fft_mag_valido,
            espectro_listo => fft_listo
        );

    inst_matching: matching_euclidiano
        port map (
            CLK_SYS        => CLK_SYS,
            RST            => rst_interno,
            magnitud_dato  => fft_mag_dato,
            magnitud_bin   => fft_mag_bin,
            magnitud_valido=> fft_mag_valido,
            espectro_listo => fft_listo,
            id_comando     => match_id_cmd,
            comando_valido => match_valido
        );

    inst_uart: uart_tx
        generic map (CICLOS_POR_BIT => 2812)
        port map (
            CLK_SYS        => CLK_SYS,
            RST            => rst_interno,
            id_comando     => match_id_cmd,
            comando_valido => match_valido,
            uart_tx_pin    => PIN_UART_TX,
            listo          => uart_listo,
            transmitiendo  => uart_tx_activo
        );

    -- ─── LEDs activo-bajo ────────────────────────────
    -- '0' = LED encendido, '1' = LED apagado
    LED_VOZ <= not voz_activa;
    LED_TX  <= not uart_tx_activo;

end architecture rtl;