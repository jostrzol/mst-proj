/* WiFi station Example

   This example code is in the Public Domain (or CC0 licensed, at your option.)

   Unless required by applicable law or agreed to in writing, this
   software is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
   CONDITIONS OF ANY KIND, either express or implied.
*/
#include <string.h>

#include "esp_err.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_modbus_common.h"
#include "esp_wifi.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"

#include "wifi.h"

/* The examples use WiFi configuration that you can set via project
   configuration menu

   If you'd rather not, just change the below entries to strings with
   the config you want - ie #define EXAMPLE_WIFI_SSID "mywifissid"
*/
#define EXAMPLE_ESP_WIFI_SSID CONFIG_ESP_WIFI_SSID
#define EXAMPLE_ESP_WIFI_PASS CONFIG_ESP_WIFI_PASSWORD
#define EXAMPLE_ESP_MAXIMUM_RETRY CONFIG_ESP_MAXIMUM_RETRY

#define ESP_WIFI_SCAN_AUTH_MODE_THRESHOLD WIFI_AUTH_WPA2_PSK

/* FreeRTOS event group to signal when we are connected*/
static EventGroupHandle_t s_wifi_event_group;

/* The event group allows multiple bits for each event, but we only care about
 * two events:
 * - we are connected to the AP with an IP
 * - we failed to connect after the maximum amount of retries */
#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT BIT1

static const char *TAG = "wifi station";

static int s_retry_num = 0;

static void event_handler(
    void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data
) {
  if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
    esp_wifi_connect();
  } else if (event_base == WIFI_EVENT &&
             event_id == WIFI_EVENT_STA_DISCONNECTED) {
    if (s_retry_num < EXAMPLE_ESP_MAXIMUM_RETRY) {
      esp_wifi_connect();
      s_retry_num++;
      ESP_LOGI(TAG, "retry to connect to the AP");
    } else {
      xEventGroupSetBits(s_wifi_event_group, WIFI_FAIL_BIT);
    }
    ESP_LOGI(TAG, "connect to the AP fail");
  } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    ESP_LOGI(TAG, "got ip:" IPSTR, IP2STR(&event->ip_info.ip));
    s_retry_num = 0;
    xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
  }
}

esp_err_t my_wifi_init(my_wifi_t *self) {
  esp_err_t err;

  // Init
  s_wifi_event_group = xEventGroupCreate();

  ESP_ERROR_CHECK(esp_netif_init());

  self->netif = esp_netif_create_default_wifi_sta();

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  err = esp_wifi_init(&cfg);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_wifi_init fail, returns(0x%x).", (int)err
  );

  // Handlers
  esp_event_handler_instance_t instance_any_id;
  err = esp_event_handler_instance_register(
      WIFI_EVENT, ESP_EVENT_ANY_ID, &event_handler, NULL, &instance_any_id
  );
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_event_handler_instance_register fail, returns(0x%x).", (int)err
  );

  esp_event_handler_instance_t instance_got_ip;
  err = esp_event_handler_instance_register(
      IP_EVENT, IP_EVENT_STA_GOT_IP, &event_handler, NULL, &instance_got_ip
  );
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_event_handler_instance_register fail, returns(0x%x).", (int)err
  );

  // Config
  wifi_config_t wifi_config = {
      .sta =
          {
              .ssid = EXAMPLE_ESP_WIFI_SSID,
              .password = EXAMPLE_ESP_WIFI_PASS,
              .threshold.authmode = WIFI_AUTH_WPA2_PSK,
              .sae_pwe_h2e = WPA3_SAE_PWE_UNSPECIFIED,
              .sae_h2e_identifier = "",
          },
  };
  err = esp_wifi_set_mode(WIFI_MODE_STA);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_wifi_set_mode fail, returns(0x%x).", (int)err
  );
  err = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_wifi_set_config fail, returns(0x%x).", (int)err
  );
  err = esp_wifi_start();
  MB_RETURN_ON_FALSE(
      (err == ESP_OK), ESP_ERR_INVALID_STATE, TAG,
      "esp_wifi_start fail, returns(0x%x).", (int)err
  );

  /* Waiting until either the connection is established (WIFI_CONNECTED_BIT) or
   * connection failed for the maximum number of re-tries (WIFI_FAIL_BIT). The
   * bits are set by event_handler() (see above) */
  EventBits_t bits = xEventGroupWaitBits(
      s_wifi_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT, pdFALSE, pdFALSE,
      portMAX_DELAY
  );

  /* xEventGroupWaitBits() returns the bits before the call returned, hence we
   * can test which event actually happened. */
  if (bits & WIFI_CONNECTED_BIT) {
    ESP_LOGI(
        TAG, "connected to ap SSID:%s password:%s", EXAMPLE_ESP_WIFI_SSID,
        EXAMPLE_ESP_WIFI_PASS
    );
  } else if (bits & WIFI_FAIL_BIT) {
    ESP_LOGI(
        TAG, "Failed to connect to SSID:%s, password:%s", EXAMPLE_ESP_WIFI_SSID,
        EXAMPLE_ESP_WIFI_PASS
    );
  } else {
    ESP_LOGE(TAG, "UNEXPECTED EVENT");
  }

  return ESP_OK;
}

void my_wifi_deinit(my_wifi_t *self) {
  esp_netif_destroy_default_wifi(self->netif);
}
