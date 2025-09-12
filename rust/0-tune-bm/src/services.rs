use core::convert::TryInto;

use embedded_svc::wifi::{AuthMethod, ClientConfiguration, Configuration};

use esp_idf_hal::modem::Modem;
use esp_idf_svc::mdns::EspMdns;
use esp_idf_svc::netif::EspNetif;
use esp_idf_svc::wifi::{BlockingWifi, EspWifi};
use esp_idf_svc::{eventloop::EspSystemEventLoop, nvs::EspDefaultNvsPartition};
use log::info;

pub struct Services<'a> {
    wifi: BlockingWifi<EspWifi<'a>>,
    #[allow(dead_code)] // For resource allocation
    mdns: EspMdns,
}

impl<'a> Services<'a> {
    pub fn new(
        modem: Modem,
        ssid: &'static str,
        password: &'static str,
    ) -> anyhow::Result<Services<'a>> {
        let nvs = EspDefaultNvsPartition::take()?;

        let sys_loop = EspSystemEventLoop::take()?;

        let mdns = mdns_init()?;

        let mut wifi =
            BlockingWifi::wrap(EspWifi::new(modem, sys_loop.clone(), Some(nvs))?, sys_loop)?;

        let ip_info = wifi.wifi().sta_netif().get_ip_info()?;
        info!("Wifi DHCP info: {:?}", ip_info);

        Self::connect_wifi(&mut wifi, ssid, password)?;

        Ok(Services { wifi, mdns })
    }

    fn connect_wifi(
        wifi: &mut BlockingWifi<EspWifi<'static>>,
        ssid: &'static str,
        password: &'static str,
    ) -> anyhow::Result<()> {
        let wifi_configuration: Configuration = Configuration::Client(ClientConfiguration {
            ssid: ssid.try_into().unwrap(),
            bssid: None,
            auth_method: AuthMethod::WPA2Personal,
            password: password.try_into().unwrap(),
            channel: None,
            ..Default::default()
        });

        wifi.set_configuration(&wifi_configuration)?;

        wifi.start()?;
        info!("Wifi started");

        wifi.connect()?;
        info!("Wifi connected");

        wifi.wait_netif_up()?;
        info!("Wifi netif up");

        Ok(())
    }

    pub fn netif(&self) -> &EspNetif {
        self.wifi.wifi().sta_netif()
    }
}

fn mdns_init() -> anyhow::Result<EspMdns> {
    let mut mdns = EspMdns::take()?;
    mdns.set_hostname("mst")?;
    mdns.add_service(Some("mst"), "_modbus", "_tcp", 502, &[("board", "esp32")])?;
    Ok(mdns)
}
