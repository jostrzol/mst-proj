#include "esp_err.h"
#include "esp_event.h"
#include "esp_log.h"
#include "mdns.h"
#include "nvs_flash.h"

#include "services.h"

#define MB_MDNS_PORT (502)
#define MB_MDNS_HOSTNAME "mst"

static const char TAG[] = "services";

esp_err_t my_mdns_init(void) {
  esp_err_t err;

  err = mdns_init();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mdns_init fail (0x%x)", (int)err);
    return err;
  }

  err = mdns_hostname_set(MB_MDNS_HOSTNAME);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mdns_hostname_set fail (0x%x)", (int)err);
    mdns_free();
    return err;
  }
  ESP_LOGI(TAG, "mdns hostname set to: [%s]", MB_MDNS_HOSTNAME);

  mdns_txt_item_t serviceTxtData[] = {{"board", "esp32"}};

  err = mdns_service_add(
      MB_MDNS_HOSTNAME, "_modbus", "_tcp", MB_MDNS_PORT, serviceTxtData, 1
  );
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "mdns_service_add fail (0x%x)", (int)err);
    mdns_free();
    return err;
  }

  return ESP_OK;
}

void my_mdns_deinit(void) { mdns_free(); }

esp_err_t services_init(services_t *self) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
      err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    err = nvs_flash_erase();
    if (err != ESP_OK) {
      ESP_LOGE(TAG, "nvs_flash_erase (0x%x)", (int)err);
      return err;
    }
    err = nvs_flash_init();
  }
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "nvs_flash_init fail (0x%x)", (int)err);
    return err;
  }

  err = esp_event_loop_create_default();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_event_loop_create_default fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(nvs_flash_deinit());
    return err;
  }

  err = my_mdns_init();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "my_mdns_init fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_event_loop_delete_default());
    ESP_ERROR_CHECK_WITHOUT_ABORT(nvs_flash_deinit());
    return err;
  }

  err = my_wifi_init(&self->wifi);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "my_wifi_init fail (0x%x)", (int)err);
    my_mdns_deinit();
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_event_loop_delete_default());
    ESP_ERROR_CHECK_WITHOUT_ABORT(nvs_flash_deinit());
    return err;
  }

  return ESP_OK;
}

void services_deinit(services_t *self) {
  my_wifi_deinit(&self->wifi);
  ESP_ERROR_CHECK_WITHOUT_ABORT(esp_event_loop_delete_default());
  ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
  ESP_ERROR_CHECK_WITHOUT_ABORT(nvs_flash_deinit());
  my_mdns_deinit();
}
